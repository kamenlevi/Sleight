import Foundation

/// Continuous gesture kinds the engine can recognize.
enum ContinuousGesture: Equatable {
    case twoFingerDial
    case threeFingerDial
    case slider
    case custom(id: UUID, fingerCount: Int)

    var fingerCount: Int {
        switch self {
        case .twoFingerDial, .slider: 2
        case .threeFingerDial: 3
        case .custom(_, let count): count
        }
    }
}

/// Per-device gesture state machine. Runs on the touch queue.
///
/// Lifecycle: fingers land -> `tracking` while we decide what the motion is.
/// Once a recognizer's criteria are met the engine goes `active` and owns the
/// touches until they lift. If a finger lifts mid-gesture but at least one
/// stays down, the gesture is `suspended`: it resumes seamlessly when the
/// finger count is restored, OR a *different* gesture can activate from the
/// remaining fingers (adjust brightness, keep the thumb down, dial volume).
/// If the motion is clearly plain scrolling, the engine goes `dead` and stays
/// out of the way until all fingers lift.
///
/// The engine also drives "screen freezing": the instant a landing posture or
/// early motion looks like a gesture, the coordinator starts swallowing
/// scroll/swipe input so pages can't move or navigate while the gesture forms.
final class GestureEngine {
    private enum Phase {
        case idle
        case tracking
        case active(ContinuousGesture)
        case suspended(ContinuousGesture, since: Double)
        case dead
    }

    private struct TouchRecord {
        let startPoint: SIMD2<Float>
        let startTime: Double
        var point: SIMD2<Float>

        var displacement: Float { length(point - startPoint) }
    }

    // Tuning constants, in normalized trackpad units (whole pad = 1.0) and
    // radians. The discriminators keep dials and sliders from firing during
    // ordinary scrolls; change with care.
    private enum Tuning {
        static let dialStartRotation: Float = 0.10        // ~6 degrees
        static let dialMaxTranslation: Float = 0.09
        static let dialMinSpread: Float = 0.05
        // Scrolling moves both fingers in the same direction (cosine ~ +1);
        // dialing moves them in opposing directions (~ -1). Require clearly
        // non-parallel motion before a dial can activate.
        static let dialMaxParallelism: Float = 0.55
        static let earlyFreezeRotation: Float = 0.04
        static let earlyFreezeMaxTranslation: Float = 0.05
        // Dial fingers land spread apart (thumb + index); scroll fingers sit
        // close together. Wide-spread landings freeze scrolling instantly.
        static let freezePostureSpread: Float = 0.17
        // Evidence the frozen candidate is actually a scroll: parallel motion
        // with no rotation — release the freeze early.
        static let unfreezeParallelism: Float = 0.6
        static let unfreezeMinDisplacement: Float = 0.03
        static let scrollFailTranslation: Float = 0.11
        static let scrollFailMaxRotation: Float = 0.06
        static let sliderEdgeStrip: Float = 0.15
        static let sliderRailAlignment: Float = 0.25      // max |x1-x2| at start
        static let sliderMinTravel: Float = 0.045
        static let sliderAxisDominance: Float = 2.0
        static let sliderRange: Float = 0.70              // pad fraction = full range
        static let customMinTravel: Float = 0.05
        static let customStationaryLimit: Float = 0.04
        static let customChordDwell: Double = 0.30
        static let customSlowMinSeconds: Double = 0.18
        static let customFastMaxSeconds: Double = 0.12
        static let suspendTimeout: Double = 10.0
        static let tapMaxDuration: Double = 0.35
        static let tapMaxDisplacement: Float = 0.025
        static let maxPerFrameRotation: Float = 0.5       // spike guard
        static let minMotionForParallelism: Float = 0.0015
    }

    var config = SleightConfig()
    let deviceID: UInt
    private weak var coordinator: GestureCoordinator?

    private var phase: Phase = .idle
    private var records: [Int32: TouchRecord] = [:]
    private var centroidAtStableCount = SIMD2<Float>(0, 0)
    private var stableSince: Double = 0
    private var rotationAccum: Float = 0
    private var parallelismEMA: Float = 0
    private var firstDownTime: Double = 0
    private var maxTouchCount = 0
    private var maxDisplacement: Float = 0
    private var candidateFrozen = false
    /// touch id -> finger index of the active custom gesture.
    private var customAssignment: [Int32: Int] = [:]

    init(deviceID: UInt, coordinator: GestureCoordinator) {
        self.deviceID = deviceID
        self.coordinator = coordinator
    }

    func process(_ frame: TouchFrame) {
        let touches = frame.touches

        guard config.enabled else {
            switch phase {
            case .active, .suspended: coordinator?.gestureEnded()
            default: break
            }
            clearCandidateFreeze()
            phase = .idle
            records = [:]
            return
        }

        if touches.isEmpty {
            handleAllLifted(at: frame.timestamp)
            return
        }

        let setChanged = Set(records.keys) != Set(touches.map(\.id))

        switch phase {
        case .idle:
            beginTracking(touches, at: frame.timestamp, freshGesture: true)

        case .tracking:
            if setChanged {
                // Fingers are still settling (staggered landing) or lifting.
                // Restart measurement with the new set but keep gesture-level
                // bookkeeping (first down time, max count) for tap detection.
                beginTracking(touches, at: frame.timestamp, freshGesture: false)
            } else {
                updateTracking(touches, at: frame.timestamp)
            }

        case .active(let gesture):
            if setChanged {
                suspend(gesture, touches: touches, at: frame.timestamp)
            } else {
                continueGesture(gesture, touches: touches)
            }

        case .suspended(let gesture, let since):
            if frame.timestamp - since > Tuning.suspendTimeout {
                coordinator?.gestureEnded()
                phase = .dead
                resetMeasurement(touches, at: frame.timestamp)
            } else if touches.count == gesture.fingerCount, !setChanged {
                resume(gesture, touches: touches, at: frame.timestamp)
            } else if setChanged {
                resetMeasurement(touches, at: frame.timestamp)
            } else {
                // The remaining/new fingers may be starting a *different*
                // gesture (adjust brightness, keep the thumb down, start the
                // volume dial). Measure like a fresh tracking phase; a new
                // activation's gestureBegan replaces the old session.
                updateMeasurement(touches)
                _ = evaluateActivations(touches, at: frame.timestamp)
            }

        case .dead:
            resetMeasurementIfSetChanged(setChanged, touches, at: frame.timestamp)
        }
    }

    // MARK: - Tracking

    private func beginTracking(_ touches: [Touch], at time: Double, freshGesture: Bool) {
        if freshGesture {
            firstDownTime = time
            maxTouchCount = 0
            maxDisplacement = 0
            phase = .tracking
        }
        maxTouchCount = max(maxTouchCount, touches.count)
        resetMeasurement(touches, at: time)

        // Posture-based early freeze: fingers landing in a shape that only a
        // gesture uses (slider rails, a custom gesture's zones) freezes
        // scrolling instantly, before any motion happens.
        if config.freezeScreen, postureMatchesGesture(touches) {
            setCandidateFreeze(true)
        }
    }

    private func resetMeasurement(_ touches: [Touch], at time: Double) {
        var newRecords: [Int32: TouchRecord] = [:]
        for touch in touches {
            if let existing = records[touch.id] {
                var updated = existing
                updated.point = touch.point
                newRecords[touch.id] = updated
            } else {
                newRecords[touch.id] = TouchRecord(startPoint: touch.point, startTime: time, point: touch.point)
            }
        }
        records = newRecords
        centroidAtStableCount = centroid(of: touches)
        stableSince = time
        rotationAccum = 0
        parallelismEMA = 0
    }

    private func resetMeasurementIfSetChanged(_ setChanged: Bool, _ touches: [Touch], at time: Double) {
        if setChanged {
            resetMeasurement(touches, at: time)
        } else {
            for touch in touches {
                records[touch.id]?.point = touch.point
            }
        }
    }

    /// Advance rotation/parallelism accumulators and per-touch records.
    private func updateMeasurement(_ touches: [Touch]) {
        let frameRotation = meanAngularDelta(touches: touches)
        if abs(frameRotation) < Tuning.maxPerFrameRotation {
            rotationAccum += frameRotation
        }
        updateParallelism(touches: touches)
        for touch in touches {
            records[touch.id]?.point = touch.point
        }
        for record in records.values {
            maxDisplacement = max(maxDisplacement, record.displacement)
        }
    }

    private func updateTracking(_ touches: [Touch], at time: Double) {
        updateMeasurement(touches)

        let translation = centroid(of: touches) - centroidAtStableCount
        let count = touches.count

        if evaluateActivations(touches, at: time) != nil { return }

        // Motion-based early freeze: rotation is building and the fingers
        // aren't moving in parallel — this is a dial forming, not a scroll.
        if config.freezeScreen, !candidateFrozen, count == 2 || count == 3,
           abs(rotationAccum) > Tuning.earlyFreezeRotation,
           length(translation) < Tuning.earlyFreezeMaxTranslation,
           parallelismEMA < Tuning.dialMaxParallelism {
            setCandidateFreeze(true)
        }

        // Frozen on posture but the motion says plain scroll (parallel, no
        // rotation): release the freeze so the scroll works with minimal loss.
        if candidateFrozen,
           parallelismEMA > Tuning.unfreezeParallelism,
           maxDisplacement > Tuning.unfreezeMinDisplacement,
           abs(rotationAccum) < Tuning.earlyFreezeRotation {
            setCandidateFreeze(false)
        }

        // Clear scroll / swipe: give up until all fingers lift so we never
        // misfire mid-scroll.
        if length(translation) > Tuning.scrollFailTranslation,
           abs(rotationAccum) < Tuning.scrollFailMaxRotation {
            clearCandidateFreeze()
            phase = .dead
        }
    }

    private func updateParallelism(touches: [Touch]) {
        var vectors: [SIMD2<Float>] = []
        for touch in touches {
            guard let record = records[touch.id] else { continue }
            let v = touch.point - record.point
            if length(v) > Tuning.minMotionForParallelism {
                vectors.append(v)
            }
        }
        guard vectors.count >= 2 else { return }
        var total: Float = 0
        var pairs = 0
        for i in 0..<vectors.count {
            for j in (i + 1)..<vectors.count {
                total += dot(normalize(vectors[i]), normalize(vectors[j]))
                pairs += 1
            }
        }
        let sample = total / Float(pairs)
        parallelismEMA = parallelismEMA * 0.7 + sample * 0.3
    }

    // MARK: - Activation

    /// Try every recognizer, most specific first. Returns the activated
    /// gesture, having already moved to `.active` and begun the session.
    private func evaluateActivations(_ touches: [Touch], at time: Double) -> ContinuousGesture? {
        let translation = centroid(of: touches) - centroidAtStableCount
        if let gesture = tryActivateCustom(touches, at: time) { return gesture }
        if touches.count == 2, let gesture = tryActivateSlider(touches, translation: translation) { return gesture }
        if touches.count == 2 || touches.count == 3,
           let gesture = tryActivateDial(touches, translation: length(translation)) { return gesture }
        return nil
    }

    private func tryActivateSlider(_ touches: [Touch], translation: SIMD2<Float>) -> ContinuousGesture? {
        let cfg = config.slider
        guard cfg.enabled, cfg.control != .none else { return nil }
        guard let a = records[touches[0].id], let b = records[touches[1].id] else { return nil }

        guard railsPosture(a.startPoint, b.startPoint) else { return nil }
        guard abs(translation.x) > Tuning.sliderMinTravel,
              abs(translation.x) > Tuning.sliderAxisDominance * abs(translation.y) else { return nil }

        activate(.slider, control: cfg.control)
        // Apply the travel that accumulated during recognition so the slider
        // has zero perceptible dead zone.
        emitSlider(translation: translation, config: cfg)
        return .slider
    }

    private func railsPosture(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>) -> Bool {
        let (top, bottom) = p1.y >= p2.y ? (p1, p2) : (p2, p1)
        return top.y > 1 - Tuning.sliderEdgeStrip
            && bottom.y < Tuning.sliderEdgeStrip
            && abs(top.x - bottom.x) < Tuning.sliderRailAlignment
    }

    private func tryActivateDial(_ touches: [Touch], translation: Float) -> ContinuousGesture? {
        let cfg = touches.count == 2 ? config.twoFingerDial : config.threeFingerDial
        guard cfg.enabled, cfg.control != .none else { return nil }
        guard abs(rotationAccum) > Tuning.dialStartRotation,
              translation < Tuning.dialMaxTranslation,
              spread(of: touches) > Tuning.dialMinSpread,
              parallelismEMA < Tuning.dialMaxParallelism else { return nil }

        let gesture: ContinuousGesture = touches.count == 2 ? .twoFingerDial : .threeFingerDial
        activate(gesture, control: cfg.control)
        // Apply the rotation that accumulated during recognition so the dial
        // has zero perceptible dead zone.
        emitDial(delta: rotationAccum, config: cfg)
        return gesture
    }

    private func tryActivateCustom(_ touches: [Touch], at time: Double) -> ContinuousGesture? {
        for gesture in config.customGestures where gesture.enabled && gesture.fingers.count == touches.count {
            guard let assignment = matchPosture(gesture, touches: touches, byStartPoint: true) else { continue }

            var alongTravels: [Float] = []
            var stationaryOK = true
            for touch in touches {
                guard let record = records[touch.id], let index = assignment[touch.id] else { continue }
                let finger = gesture.fingers[index]
                let displacement = record.point - record.startPoint
                if let direction = finger.direction.vector {
                    let along = dot(displacement, direction)
                    let perpendicular = length(displacement - along * direction)
                    guard along > 0, perpendicular < max(Tuning.customStationaryLimit, along * 0.6) else {
                        alongTravels = []
                        break
                    }
                    alongTravels.append(along)
                } else if record.displacement > Tuning.customStationaryLimit {
                    stationaryOK = false
                    break
                }
            }
            guard stationaryOK else { continue }

            let hasMovers = gesture.fingers.contains { $0.direction != .none }
            if hasMovers {
                guard let minTravel = alongTravels.min(), alongTravels.count == gesture.fingers.filter({ $0.direction != .none }).count,
                      minTravel > Tuning.customMinTravel else { continue }
                let elapsed = time - stableSince
                switch gesture.speed {
                case .any: break
                case .slow: guard elapsed > Tuning.customSlowMinSeconds else { continue }
                case .fast: guard elapsed < Tuning.customFastMaxSeconds else { continue }
                }
            } else {
                // A chord: all fingers stationary in their zones. Trigger on
                // dwell. Only meaningful for discrete actions.
                guard !gesture.isContinuous, time - stableSince > Tuning.customChordDwell else { continue }
            }

            if gesture.isContinuous {
                guard gesture.control != .none else { continue }
                customAssignment = assignment
                let kind = ContinuousGesture.custom(id: gesture.id, fingerCount: gesture.fingers.count)
                activate(kind, control: gesture.control)
                // Apply travel accumulated during recognition.
                emitCustom(gesture, touches: touches, sinceStart: true)
                return kind
            } else {
                if case .suspended = phase {
                    coordinator?.gestureEnded()
                }
                coordinator?.performDiscrete(
                    action: gesture.action,
                    appPath: gesture.appPath,
                    shellCommand: gesture.shellCommand,
                    targetApp: gesture.targetApp
                )
                clearCandidateFreeze()
                phase = .dead
                return nil
            }
        }
        return nil
    }

    private func activate(_ gesture: ContinuousGesture, control: ContinuousControl) {
        phase = .active(gesture)
        candidateFrozen = false // superseded by full gesture suppression
        coordinator?.gestureBegan(control: control, deviceID: deviceID)
    }

    /// Greedy nearest-match of touches onto a custom gesture's finger zones.
    /// If the gesture has a drawn boundary, every finger must land inside it.
    private func matchPosture(_ gesture: CustomGesture, touches: [Touch], byStartPoint: Bool) -> [Int32: Int]? {
        var available = Set(gesture.fingers.indices)
        var assignment: [Int32: Int] = [:]
        let boundary = (gesture.boundary?.count ?? 0) >= 3 ? gesture.boundary : nil
        for touch in touches {
            let point = byStartPoint ? (records[touch.id]?.startPoint ?? touch.point) : touch.point
            if let boundary, !pointInPolygon(point, boundary) { return nil }
            var best: (index: Int, distance: Float)?
            for index in available {
                let finger = gesture.fingers[index]
                let center = SIMD2<Float>(Float(finger.x), Float(finger.y))
                let distance = length(point - center)
                if distance < Float(finger.radius), distance < (best?.distance ?? .infinity) {
                    best = (index, distance)
                }
            }
            guard let best else { return nil }
            available.remove(best.index)
            assignment[touch.id] = best.index
        }
        return assignment
    }

    /// Does the landing posture match any gesture that can be identified
    /// from positions alone (slider rails, a custom gesture's zones, or the
    /// wide finger spread of a dial grip)?
    private func postureMatchesGesture(_ touches: [Touch]) -> Bool {
        if touches.count == 2, config.slider.enabled, config.slider.control != .none,
           let a = records[touches[0].id], let b = records[touches[1].id],
           railsPosture(a.startPoint, b.startPoint) {
            return true
        }
        // A dial grip lands with fingers spread apart (thumb + index);
        // scrolling fingers sit close together. If the spread posture turns
        // out to be a scroll after all, the freeze is released as soon as
        // parallel motion shows up.
        let dialConfig = touches.count == 2 ? config.twoFingerDial : config.threeFingerDial
        if (touches.count == 2 || touches.count == 3),
           dialConfig.enabled, dialConfig.control != .none,
           spread(of: touches) > Tuning.freezePostureSpread {
            return true
        }
        for gesture in config.customGestures where gesture.enabled && gesture.fingers.count == touches.count {
            if matchPosture(gesture, touches: touches, byStartPoint: true) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Suspend / resume

    private func suspend(_ gesture: ContinuousGesture, touches: [Touch], at time: Double) {
        phase = .suspended(gesture, since: time)
        resetMeasurement(touches, at: time)
        coordinator?.gestureSuspended()
    }

    private func resume(_ gesture: ContinuousGesture, touches: [Touch], at time: Double) {
        records = [:]
        resetMeasurement(touches, at: time)
        if case .custom(let id, _) = gesture,
           let custom = config.customGestures.first(where: { $0.id == id }) {
            // Fingers may have drifted from their zones; best-effort re-match
            // by current position, ignoring zone radii.
            customAssignment = rematchIgnoringRadius(custom, touches: touches)
        }
        phase = .active(gesture)
        coordinator?.gestureResumed()
    }

    private func rematchIgnoringRadius(_ gesture: CustomGesture, touches: [Touch]) -> [Int32: Int] {
        var available = Set(gesture.fingers.indices)
        var assignment: [Int32: Int] = [:]
        for touch in touches {
            var best: (index: Int, distance: Float)?
            for index in available {
                let finger = gesture.fingers[index]
                let distance = length(touch.point - SIMD2(Float(finger.x), Float(finger.y)))
                if distance < (best?.distance ?? .infinity) {
                    best = (index, distance)
                }
            }
            if let best {
                available.remove(best.index)
                assignment[touch.id] = best.index
            }
        }
        return assignment
    }

    // MARK: - Active gesture updates

    private func continueGesture(_ gesture: ContinuousGesture, touches: [Touch]) {
        switch gesture {
        case .twoFingerDial, .threeFingerDial:
            let cfg = gesture == .twoFingerDial ? config.twoFingerDial : config.threeFingerDial
            let delta = meanAngularDelta(touches: touches)
            for touch in touches {
                records[touch.id]?.point = touch.point
            }
            if abs(delta) < Tuning.maxPerFrameRotation {
                emitDial(delta: delta, config: cfg)
            }

        case .slider:
            let delta = frameCentroidDelta(touches)
            emitSlider(translation: delta, config: config.slider)

        case .custom(let id, _):
            guard let custom = config.customGestures.first(where: { $0.id == id }) else {
                coordinator?.gestureEnded()
                phase = .dead
                return
            }
            emitCustom(custom, touches: touches, sinceStart: false)
        }
    }

    private func frameCentroidDelta(_ touches: [Touch]) -> SIMD2<Float> {
        var previousCentroid = SIMD2<Float>(0, 0)
        for touch in touches {
            previousCentroid += records[touch.id]?.point ?? touch.point
        }
        previousCentroid /= Float(touches.count)
        let delta = centroid(of: touches) - previousCentroid
        for touch in touches {
            records[touch.id]?.point = touch.point
        }
        return delta
    }

    private func emitDial(delta: Float, config cfg: DialConfig) {
        // Clockwise (negative math angle) turns the value up, like a real knob.
        let sign: Float = cfg.inverted ? 1 : -1
        let change = sign * delta / (2 * .pi) * Float(cfg.sensitivity)
        coordinator?.gestureChanged(delta: change)
    }

    private func emitSlider(translation: SIMD2<Float>, config cfg: SliderConfig) {
        let sign: Float = cfg.inverted ? -1 : 1
        let change = sign * translation.x / Tuning.sliderRange * Float(cfg.sensitivity)
        coordinator?.gestureChanged(delta: change)
    }

    private func emitCustom(_ gesture: CustomGesture, touches: [Touch], sinceStart: Bool) {
        var total: Float = 0
        var movers = 0
        for touch in touches {
            guard let record = records[touch.id],
                  let index = customAssignment[touch.id],
                  index < gesture.fingers.count,
                  let direction = gesture.fingers[index].direction.vector else { continue }
            let reference = sinceStart ? record.startPoint : record.point
            total += dot(touch.point - reference, direction)
            movers += 1
        }
        for touch in touches {
            records[touch.id]?.point = touch.point
        }
        guard movers > 0 else { return }
        let mean = total / Float(movers)
        let change = mean / Tuning.sliderRange * Float(gesture.sensitivity)
        coordinator?.gestureChanged(delta: change)
    }

    // MARK: - Lift / taps

    private func handleAllLifted(at time: Double) {
        switch phase {
        case .active, .suspended:
            coordinator?.gestureEnded()
        case .tracking, .dead:
            let duration = time - firstDownTime
            if duration < Tuning.tapMaxDuration,
               maxDisplacement < Tuning.tapMaxDisplacement,
               (3...5).contains(maxTouchCount) {
                coordinator?.tapDetected(fingerCount: maxTouchCount)
            }
        case .idle:
            break
        }
        clearCandidateFreeze()
        phase = .idle
        records = [:]
        customAssignment = [:]
        rotationAccum = 0
        parallelismEMA = 0
        maxTouchCount = 0
        maxDisplacement = 0
    }

    /// Ray-casting point-in-polygon test in normalized pad coordinates.
    private func pointInPolygon(_ point: SIMD2<Float>, _ polygon: [BoundaryPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            let ax = Float(a.x), ay = Float(a.y)
            let bx = Float(b.x), by = Float(b.y)
            if (ay > point.y) != (by > point.y),
               point.x < (bx - ax) * (point.y - ay) / (by - ay) + ax {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: - Candidate freeze plumbing

    private func setCandidateFreeze(_ on: Bool) {
        guard candidateFrozen != on else { return }
        candidateFrozen = on
        coordinator?.candidateFreezeChanged(on)
    }

    private func clearCandidateFreeze() {
        setCandidateFreeze(false)
    }

    // MARK: - Geometry

    private func centroid(of touches: [Touch]) -> SIMD2<Float> {
        var sum = SIMD2<Float>(0, 0)
        for touch in touches { sum += touch.point }
        return sum / Float(touches.count)
    }

    private func spread(of touches: [Touch]) -> Float {
        let c = centroid(of: touches)
        var total: Float = 0
        for touch in touches { total += length(touch.point - c) }
        return total / Float(touches.count)
    }

    private func angle(of point: SIMD2<Float>, around center: SIMD2<Float>) -> Float {
        atan2f(point.y - center.y, point.x - center.x)
    }

    /// Mean signed rotation of the touch set around its centroid since the
    /// previous frame. Translation cancels out because angles are measured
    /// against each frame's own centroid.
    private func meanAngularDelta(touches: [Touch]) -> Float {
        var previousPoints: [SIMD2<Float>] = []
        var currentPoints: [SIMD2<Float>] = []
        for touch in touches {
            guard let record = records[touch.id] else { continue }
            previousPoints.append(record.point)
            currentPoints.append(touch.point)
        }
        guard previousPoints.count >= 2 else { return 0 }

        var previousCentroid = SIMD2<Float>(0, 0)
        var currentCentroid = SIMD2<Float>(0, 0)
        for p in previousPoints { previousCentroid += p }
        for p in currentPoints { currentCentroid += p }
        previousCentroid /= Float(previousPoints.count)
        currentCentroid /= Float(currentPoints.count)

        var sum: Float = 0
        for i in 0..<previousPoints.count {
            let before = angle(of: previousPoints[i], around: previousCentroid)
            let after = angle(of: currentPoints[i], around: currentCentroid)
            var delta = after - before
            delta = atan2f(sinf(delta), cosf(delta))
            sum += delta
        }
        return sum / Float(previousPoints.count)
    }
}

// MARK: - Small vector helpers

private func length(_ v: SIMD2<Float>) -> Float {
    (v.x * v.x + v.y * v.y).squareRoot()
}

private func dot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    a.x * b.x + a.y * b.y
}

private func normalize(_ v: SIMD2<Float>) -> SIMD2<Float> {
    let l = length(v)
    return l > 0 ? v / l : v
}
