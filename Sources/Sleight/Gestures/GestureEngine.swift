import Foundation

/// Continuous gesture kinds the engine can recognize.
enum ContinuousGesture {
    case twoFingerDial
    case threeFingerDial
    case slider

    var fingerCount: Int {
        switch self {
        case .twoFingerDial, .slider: 2
        case .threeFingerDial: 3
        }
    }
}

/// Per-device gesture state machine. Runs on the touch queue.
///
/// Lifecycle: fingers land -> `tracking` while we decide what the motion is.
/// Once a recognizer's criteria are met the engine goes `active` and owns the
/// touches until they lift. If a finger lifts mid-gesture but at least one
/// stays down, the gesture is `suspended` and resumes seamlessly when the
/// finger count is restored — no need to restart the gesture. If the motion
/// is clearly plain scrolling, the engine goes `dead` and stays out of the
/// way until all fingers lift.
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
        static let dialMaxTranslation: Float = 0.07
        static let dialMinSpread: Float = 0.05
        // Scrolling moves both fingers in the same direction (cosine ~ +1);
        // dialing moves them in opposing directions (~ -1). Require clearly
        // non-parallel motion before a dial can activate.
        static let dialMaxParallelism: Float = 0.4
        static let scrollFailTranslation: Float = 0.11
        static let scrollFailMaxRotation: Float = 0.06
        static let sliderEdgeStrip: Float = 0.12
        static let sliderRailAlignment: Float = 0.25      // max |x1-x2| at start
        static let sliderMinTravel: Float = 0.045
        static let sliderAxisDominance: Float = 2.0
        static let sliderRange: Float = 0.70              // pad fraction = full range
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
    private var rotationAccum: Float = 0
    private var parallelismEMA: Float = 0
    private var firstDownTime: Double = 0
    private var maxTouchCount = 0
    private var maxDisplacement: Float = 0
    private var activeSliderMode: SliderMode = .verticalFromEdge

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
                rebuildRecords(touches, at: frame.timestamp)
            } else if touches.count == gesture.fingerCount {
                resume(gesture, touches: touches, at: frame.timestamp)
            } else {
                rebuildRecords(touches, at: frame.timestamp)
            }

        case .dead:
            rebuildRecords(touches, at: frame.timestamp)
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
        rotationAccum = 0
        parallelismEMA = 0
    }

    private func rebuildRecords(_ touches: [Touch], at time: Double) {
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
    }

    private func updateTracking(_ touches: [Touch], at time: Double) {
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

        let translation = centroid(of: touches) - centroidAtStableCount
        let count = touches.count

        if count == 2, tryActivateSlider(touches, translation: translation) { return }
        if count == 2 || count == 3, tryActivateDial(touches, translation: length(translation), count: count) { return }

        // Clear scroll / swipe: give up until all fingers lift so we never
        // misfire mid-scroll.
        if length(translation) > Tuning.scrollFailTranslation,
           abs(rotationAccum) < Tuning.scrollFailMaxRotation {
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

    private func tryActivateSlider(_ touches: [Touch], translation: SIMD2<Float>) -> Bool {
        let cfg = config.slider
        guard cfg.enabled, cfg.control != .none else { return false }
        guard let a = records[touches[0].id], let b = records[touches[1].id] else { return false }

        switch cfg.mode {
        case .verticalFromEdge:
            // Both fingers began in the same thin strip at the top or bottom
            // edge — a posture scrolling never starts from.
            let bothTop = a.startPoint.y > 1 - Tuning.sliderEdgeStrip && b.startPoint.y > 1 - Tuning.sliderEdgeStrip
            let bothBottom = a.startPoint.y < Tuning.sliderEdgeStrip && b.startPoint.y < Tuning.sliderEdgeStrip
            guard bothTop || bothBottom else { return false }
            guard abs(translation.y) > Tuning.sliderMinTravel,
                  abs(translation.y) > Tuning.sliderAxisDominance * abs(translation.x) else { return false }

        case .horizontalRails:
            // One finger on each edge, starting at roughly the same x,
            // sweeping sideways together.
            let (top, bottom) = a.startPoint.y >= b.startPoint.y ? (a, b) : (b, a)
            guard top.startPoint.y > 1 - Tuning.sliderEdgeStrip - 0.03,
                  bottom.startPoint.y < Tuning.sliderEdgeStrip + 0.03,
                  abs(top.startPoint.x - bottom.startPoint.x) < Tuning.sliderRailAlignment else { return false }
            guard abs(translation.x) > Tuning.sliderMinTravel,
                  abs(translation.x) > Tuning.sliderAxisDominance * abs(translation.y) else { return false }
        }

        activeSliderMode = cfg.mode
        phase = .active(.slider)
        coordinator?.gestureBegan(control: cfg.control, deviceID: deviceID)
        // Apply the travel that accumulated during recognition so the slider
        // has zero perceptible dead zone.
        emitSlider(translation: translation, config: cfg)
        return true
    }

    private func tryActivateDial(_ touches: [Touch], translation: Float, count: Int) -> Bool {
        let cfg = count == 2 ? config.twoFingerDial : config.threeFingerDial
        guard cfg.enabled, cfg.control != .none else { return false }
        guard abs(rotationAccum) > Tuning.dialStartRotation,
              translation < Tuning.dialMaxTranslation,
              spread(of: touches) > Tuning.dialMinSpread,
              parallelismEMA < Tuning.dialMaxParallelism else { return false }

        let gesture: ContinuousGesture = count == 2 ? .twoFingerDial : .threeFingerDial
        phase = .active(gesture)
        coordinator?.gestureBegan(control: cfg.control, deviceID: deviceID)
        // Apply the rotation that accumulated during recognition so the dial
        // has zero perceptible dead zone.
        emitDial(delta: rotationAccum, config: cfg)
        return true
    }

    // MARK: - Suspend / resume

    private func suspend(_ gesture: ContinuousGesture, touches: [Touch], at time: Double) {
        phase = .suspended(gesture, since: time)
        rebuildRecords(touches, at: time)
        coordinator?.gestureSuspended()
    }

    private func resume(_ gesture: ContinuousGesture, touches: [Touch], at time: Double) {
        records = [:]
        rebuildRecords(touches, at: time)
        centroidAtStableCount = centroid(of: touches)
        phase = .active(gesture)
        coordinator?.gestureResumed()
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
            let cfg = config.slider
            var previousCentroid = SIMD2<Float>(0, 0)
            for touch in touches {
                previousCentroid += records[touch.id]?.point ?? touch.point
            }
            previousCentroid /= Float(touches.count)
            let delta = centroid(of: touches) - previousCentroid
            for touch in touches {
                records[touch.id]?.point = touch.point
            }
            emitSlider(translation: delta, config: cfg)
        }
    }

    private func emitDial(delta: Float, config cfg: DialConfig) {
        // Clockwise (negative math angle) turns the value up, like a real knob.
        let sign: Float = cfg.inverted ? 1 : -1
        let change = sign * delta / (2 * .pi) * Float(cfg.sensitivity)
        coordinator?.gestureChanged(delta: change)
    }

    private func emitSlider(translation: SIMD2<Float>, config cfg: SliderConfig) {
        let travel = activeSliderMode == .verticalFromEdge ? translation.y : translation.x
        let sign: Float = cfg.inverted ? -1 : 1
        let change = sign * travel / Tuning.sliderRange * Float(cfg.sensitivity)
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
        phase = .idle
        records = [:]
        rotationAccum = 0
        parallelismEMA = 0
        maxTouchCount = 0
        maxDisplacement = 0
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
