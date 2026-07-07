import Foundation

/// Continuous gesture kinds the engine can recognize.
enum ContinuousGesture {
    case twoFingerDial
    case threeFingerDial
    case holdArc
}

/// Per-device gesture state machine. Runs on the touch queue.
///
/// Lifecycle: fingers land -> `tracking` while we decide what the motion is.
/// Once a recognizer's criteria are met the engine goes `active` and owns the
/// touches until they lift. If the motion is clearly plain scrolling, the
/// engine goes `dead` and stays out of the way until all fingers lift.
final class GestureEngine {
    private enum Phase {
        case idle
        case tracking
        case active(ContinuousGesture)
        case dead
    }

    private struct TouchRecord {
        let startPoint: SIMD2<Float>
        let startTime: Double
        var point: SIMD2<Float>

        var displacement: Float { simd_length_2(point - startPoint) }
    }

    // Tuning constants, in normalized trackpad units (whole pad = 1.0) and
    // radians. These are the product of the design in README.md; change with
    // care, the discriminators keep dials from ever firing during scrolls.
    private enum Tuning {
        static let dialStartRotation: Float = 0.10        // ~6 degrees
        static let dialMaxTranslation: Float = 0.07
        static let dialMinSpread: Float = 0.05
        static let scrollFailTranslation: Float = 0.11
        static let scrollFailMaxRotation: Float = 0.06
        static let arcAnchorMaxDrift: Float = 0.035
        static let arcMoverMinTravel: Float = 0.055
        static let arcStaggerSeconds: Double = 0.12
        static let arcDisplacementRatio: Float = 3.5
        static let tapMaxDuration: Double = 0.35
        static let tapMaxDisplacement: Float = 0.025
        static let maxPerFrameRotation: Float = 0.5       // spike guard
        static let arcSweepForFullRange: Float = 2.62     // 150 degrees
    }

    var config = SleightConfig()
    private let deviceID: UInt
    private weak var coordinator: GestureCoordinator?

    private var phase: Phase = .idle
    private var records: [Int32: TouchRecord] = [:]
    private var countStableSince: Double = 0
    private var centroidAtStableCount = SIMD2<Float>(0, 0)
    private var rotationAccum: Float = 0
    private var firstDownTime: Double = 0
    private var maxTouchCount = 0
    private var maxDisplacement: Float = 0
    private var arcAnchorID: Int32 = -1
    private var arcMoverID: Int32 = -1
    private var arcPreviousAngle: Float = 0

    init(deviceID: UInt, coordinator: GestureCoordinator) {
        self.deviceID = deviceID
        self.coordinator = coordinator
    }

    func process(_ frame: TouchFrame) {
        let touches = frame.touches

        guard config.enabled else {
            if case .active = phase { endActiveGesture() }
            phase = .idle
            records = [:]
            return
        }

        if touches.isEmpty {
            handleAllLifted(at: frame.timestamp)
            return
        }

        let previousIDs = Set(records.keys)
        let currentIDs = Set(touches.map(\.id))
        let setChanged = previousIDs != currentIDs

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
                endActiveGesture()
                phase = .dead
                records = [:]
                for touch in touches {
                    records[touch.id] = TouchRecord(startPoint: touch.point, startTime: frame.timestamp, point: touch.point)
                }
            } else {
                continueGesture(gesture, touches: touches)
            }

        case .dead:
            records = [:]
            for touch in touches {
                records[touch.id] = TouchRecord(startPoint: touch.point, startTime: frame.timestamp, point: touch.point)
            }
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
        countStableSince = time
        centroidAtStableCount = centroid(of: touches)
        rotationAccum = 0
    }

    private func updateTracking(_ touches: [Touch], at time: Double) {
        let frameRotation = meanAngularDelta(touches: touches)
        if abs(frameRotation) < Tuning.maxPerFrameRotation {
            rotationAccum += frameRotation
        }

        for touch in touches {
            records[touch.id]?.point = touch.point
        }
        for record in records.values {
            maxDisplacement = max(maxDisplacement, record.displacement)
        }

        let translation = simd_length_2(centroid(of: touches) - centroidAtStableCount)
        let count = touches.count

        // Clear scroll / swipe: give up until all fingers lift so we never
        // misfire mid-scroll.
        if translation > Tuning.scrollFailTranslation, abs(rotationAccum) < Tuning.scrollFailMaxRotation {
            phase = .dead
            return
        }

        if count == 2, tryActivateHoldArc(touches, at: time) { return }

        if count == 2 || count == 3 {
            tryActivateDial(touches, translation: translation, count: count)
        }
    }

    // MARK: - Activation

    private func tryActivateHoldArc(_ touches: [Touch], at time: Double) -> Bool {
        let cfg = config.holdArc
        guard cfg.enabled, cfg.control != .none else { return false }
        guard let a = records[touches[0].id], let b = records[touches[1].id] else { return false }

        let (anchorTouch, anchor, moverTouch, mover) =
            a.displacement <= b.displacement
                ? (touches[0], a, touches[1], b)
                : (touches[1], b, touches[0], a)

        guard anchor.displacement < Tuning.arcAnchorMaxDrift,
              mover.displacement > Tuning.arcMoverMinTravel else { return false }

        let staggered = mover.startTime - anchor.startTime >= Tuning.arcStaggerSeconds
        let ratioClear = mover.displacement > Tuning.arcDisplacementRatio * max(anchor.displacement, 0.008)
        guard staggered || ratioClear else { return false }

        arcAnchorID = anchorTouch.id
        arcMoverID = moverTouch.id
        arcPreviousAngle = angle(of: moverTouch.point, around: anchorTouch.point)
        phase = .active(.holdArc)
        coordinator?.gestureBegan(.holdArc, config: cfg)
        return true
    }

    private func tryActivateDial(_ touches: [Touch], translation: Float, count: Int) {
        let cfg = count == 2 ? config.twoFingerDial : config.threeFingerDial
        guard cfg.enabled, cfg.control != .none else { return }
        guard abs(rotationAccum) > Tuning.dialStartRotation,
              translation < Tuning.dialMaxTranslation,
              spread(of: touches) > Tuning.dialMinSpread else { return }

        let gesture: ContinuousGesture = count == 2 ? .twoFingerDial : .threeFingerDial
        phase = .active(gesture)
        coordinator?.gestureBegan(gesture, config: cfg)
        // Apply the rotation that accumulated during recognition so the dial
        // has zero perceptible dead zone.
        emitDial(gesture, delta: rotationAccum, config: cfg)
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
                emitDial(gesture, delta: delta, config: cfg)
            }

        case .holdArc:
            guard let anchor = touches.first(where: { $0.id == arcAnchorID }),
                  let mover = touches.first(where: { $0.id == arcMoverID }) else {
                endActiveGesture()
                phase = .dead
                return
            }
            let current = angle(of: mover.point, around: anchor.point)
            var delta = current - arcPreviousAngle
            delta = atan2f(sinf(delta), cosf(delta))
            arcPreviousAngle = current
            for touch in touches {
                records[touch.id]?.point = touch.point
            }
            if abs(delta) < Tuning.maxPerFrameRotation {
                let cfg = config.holdArc
                // Sweeping rightward over a resting thumb is clockwise, which
                // is negative in math coordinates; flip so rightward = up.
                let sign: Float = cfg.inverted ? 1 : -1
                let change = sign * delta / Tuning.arcSweepForFullRange * Float(cfg.sensitivity)
                coordinator?.gestureChanged(.holdArc, delta: change, config: cfg)
            }
        }
    }

    private func emitDial(_ gesture: ContinuousGesture, delta: Float, config cfg: DialConfig) {
        // Clockwise (negative math angle) turns the value up, like a real knob.
        let sign: Float = cfg.inverted ? 1 : -1
        let change = sign * delta / (2 * .pi) * Float(cfg.sensitivity)
        coordinator?.gestureChanged(gesture, delta: change, config: cfg)
    }

    private func endActiveGesture() {
        coordinator?.gestureEnded()
        arcAnchorID = -1
        arcMoverID = -1
    }

    // MARK: - Lift / taps

    private func handleAllLifted(at time: Double) {
        switch phase {
        case .active:
            endActiveGesture()
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
        for touch in touches { total += simd_length_2(touch.point - c) }
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

private func simd_length_2(_ v: SIMD2<Float>) -> Float {
    (v.x * v.x + v.y * v.y).squareRoot()
}
