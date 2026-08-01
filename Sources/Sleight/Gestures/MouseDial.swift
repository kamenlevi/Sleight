import CoreGraphics
import Foundation

/// Mouse gestures: hold the configured button and circle the mouse on the
/// desk to turn a knob, or roll the scroll wheel to step actions.
///
/// Fed by EventSuppressor's session tap (which already listens to every event
/// type), so this adds no tap of its own. Everything here happens on the tap
/// thread and must stay cheap; the actual control writes hop to a serial
/// queue and reuse the same GestureCoordinator session the trackpad dials
/// use — same HUD, same coalesced writers, same scroll suppression.
///
/// Rotation is read from the *movement direction*, not positions: each time
/// the pointer has travelled a few points, the heading of that segment is
/// compared with the previous segment's. Circling clockwise turns the heading
/// steadily one way, and the accumulated turn is the knob. This is what an
/// optical mouse can actually express — its sensor only reads translation, so
/// twisting the mouse in place is invisible; circling it is not.
final class MouseDial: @unchecked Sendable {
    static let shared = MouseDial()

    /// Marks the clicks this class re-posts, so the tap passes them through
    /// instead of capturing them again.
    static let syntheticEventTag: Int64 = 0x534C_4D44 // "SLMD"

    private let lock = NSLock()
    private var config = MouseConfig()
    private var masterEnabled = true

    private enum State {
        case idle
        /// Button is down and swallowed; not yet decided click vs. gesture.
        case armed
        /// Enough rotation accumulated: a live knob session.
        case rotating
    }
    private var state: State = .idle
    private var pressTime: Double = 0
    private var pressLocation = CGPoint.zero
    /// Total distance travelled since the press, for click-vs-gesture.
    private var travel: Double = 0
    /// Movement being accumulated into the current heading segment.
    private var segment = (dx: 0.0, dy: 0.0)
    /// The last completed segment, that the next one's heading is compared to.
    private var previous: (dx: Double, dy: Double)?
    /// Rotation accumulated while still deciding whether this is a gesture.
    private var pendingTurn: Double = 0
    private var scrollAccumulator: Double = 0
    private var usedScroll = false

    private let queue = DispatchQueue(label: "com.kamenlevi.sleight.mousedial",
                                      qos: .userInteractive)

    /// A segment must be at least this long before its heading counts —
    /// below it, sensor jitter dominates and the heading is noise.
    private let minSegment: Double = 5
    /// Accumulated turn (radians) after which the hold becomes a knob.
    /// About 60° — a deliberate arc, but well under a quarter circle.
    private let beginThreshold = 1.0
    /// One full circle sweeps this fraction of the range at sensitivity 1.
    /// (The trackpad dial uses a full fraction per rotation, but circling a
    /// mouse is a much bigger, easier motion than twisting two fingers.)
    private let rangePerTurn = 0.4

    private init() {}

    func update(config newConfig: MouseConfig, masterEnabled enabled: Bool) {
        lock.lock()
        let wasCapturing = state != .idle
        config = newConfig
        masterEnabled = enabled
        if !enabled || !newConfig.enabled { state = .idle }
        lock.unlock()
        if wasCapturing, !enabled || !newConfig.enabled {
            queue.async { GestureCoordinator.shared.gestureEnded() }
        }
    }

    // MARK: - Tap entry point

    /// Called for every event the session tap sees. Returns true when the
    /// event belongs to this engine and must be swallowed.
    func handle(event: CGEvent, type: CGEventType) -> Bool {
        // Our own re-posted clicks come back through the tap; let them by.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag {
            return false
        }

        switch type {
        case .rightMouseDown, .otherMouseDown:
            return buttonDown(event)
        case .rightMouseUp, .otherMouseUp:
            return buttonUp(event)
        case .rightMouseDragged, .otherMouseDragged:
            return dragged(event)
        case .keyDown:
            return keyDown(event)
        case .keyUp:
            return keyUp(event)
        case .mouseMoved:
            // A key-armed hold has no button down, so circling arrives as
            // plain movement rather than a drag.
            lock.lock()
            let capturing = state != .idle && config.isKeyTrigger
            lock.unlock()
            return capturing ? dragged(event) : false
        case .scrollWheel:
            return scrolled(event)
        default:
            return false
        }
    }

    // MARK: - Button

    private func buttonDown(_ event: CGEvent) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard masterEnabled, config.enabled, !config.isKeyTrigger, state == .idle,
              Int(event.getIntegerValueField(.mouseEventButtonNumber)) == config.button,
              Keystrokes.canonical(event.flags, keyCode: -1) == config.modifiers
        else { return false }

        arm(at: event.location)
        return true
    }

    /// Reset all per-hold state; caller holds the lock.
    private func arm(at location: CGPoint) {
        state = .armed
        pressTime = CFAbsoluteTimeGetCurrent()
        pressLocation = location
        travel = 0
        segment = (0, 0)
        previous = nil
        pendingTurn = 0
        scrollAccumulator = 0
        usedScroll = false
    }

    // MARK: - Keyboard trigger

    private func keyDown(_ event: CGEvent) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard masterEnabled, config.enabled, config.isKeyTrigger,
              Int(event.getIntegerValueField(.keyboardEventKeycode)) == config.keyCode
        else { return false }
        // Holding a key autorepeats; while armed, the repeats are ours too.
        if state != .idle { return true }
        guard Keystrokes.canonical(event.flags, keyCode: config.keyCode) == config.modifiers
        else { return false }

        arm(at: CGEvent(source: nil)?.location ?? .zero)
        return true
    }

    private func keyUp(_ event: CGEvent) -> Bool {
        lock.lock()
        guard state != .idle, config.isKeyTrigger,
              Int(event.getIntegerValueField(.keyboardEventKeycode)) == config.keyCode
        else {
            lock.unlock()
            return false
        }
        let wasRotating = state == .rotating
        // Same courtesy as the button: a short, still press was real typing —
        // replay it so the key's ordinary job still happens.
        let replay = !wasRotating && !usedScroll && travel < 8
            && CFAbsoluteTimeGetCurrent() - pressTime < 0.4
        let keyCode = config.keyCode
        let flags = event.flags
        state = .idle
        lock.unlock()

        queue.async {
            if wasRotating {
                GestureCoordinator.shared.gestureEnded()
            } else if replay {
                Self.postKeyTap(keyCode: keyCode, flags: flags)
            }
        }
        return true
    }

    private func buttonUp(_ event: CGEvent) -> Bool {
        lock.lock()
        guard state != .idle,
              Int(event.getIntegerValueField(.mouseEventButtonNumber)) == config.button
        else {
            lock.unlock()
            return false
        }
        let wasRotating = state == .rotating
        // A short, still press that never scrolled was a real click the user
        // wanted — replay it so the button's normal job (context menu,
        // middle-click paste, browser back) still works. It lands on release
        // rather than press; that's the cost of having to decide.
        let replayClick = !wasRotating && !usedScroll && travel < 8
            && CFAbsoluteTimeGetCurrent() - pressTime < 0.4
        let button = config.button
        let location = event.location
        state = .idle
        lock.unlock()

        queue.async {
            if wasRotating {
                GestureCoordinator.shared.gestureEnded()
            } else if replayClick {
                Self.postClick(button: button, at: location)
            }
        }
        return true
    }

    // MARK: - Rotation

    private func dragged(_ event: CGEvent) -> Bool {
        lock.lock()
        guard state != .idle else {
            lock.unlock()
            return false
        }

        let dx = Double(event.getIntegerValueField(.mouseEventDeltaX))
        let dy = Double(event.getIntegerValueField(.mouseEventDeltaY))
        travel += (dx * dx + dy * dy).squareRoot()
        segment.dx += dx
        segment.dy += dy

        let length = (segment.dx * segment.dx + segment.dy * segment.dy).squareRoot()
        guard length >= minSegment else {
            lock.unlock()
            return true // swallow: the pointer stays parked during a hold
        }

        var turn: Double = 0
        if let previous {
            // Signed angle between the previous segment's heading and this
            // one's. Screen y grows downward, so a clockwise circle (as the
            // hand sees it) gives a positive cross product — clockwise turns
            // the knob up, like hardware.
            let cross = previous.dx * segment.dy - previous.dy * segment.dx
            let dot = previous.dx * segment.dx + previous.dy * segment.dy
            turn = atan2(cross, dot)
        }
        previous = (segment.dx, segment.dy)
        segment = (0, 0)

        let cfg = config
        var began = false
        if state == .armed {
            pendingTurn += turn
            if abs(pendingTurn) >= beginThreshold {
                state = .rotating
                began = true
                turn = pendingTurn // apply the run-up, so nothing is lost
            }
        }
        let rotating = state == .rotating
        lock.unlock()

        if rotating {
            var delta = turn / (2 * .pi) * rangePerTurn * cfg.sensitivity
            if cfg.inverted { delta = -delta }
            let control = cfg.control
            queue.async {
                if began {
                    GestureCoordinator.shared.gestureBegan(control: control, deviceID: 0)
                }
                GestureCoordinator.shared.gestureChanged(delta: Float(delta))
            }
        }
        return true
    }

    // MARK: - Scroll wheel

    private func scrolled(_ event: CGEvent) -> Bool {
        lock.lock()
        guard state != .idle else {
            lock.unlock()
            return false
        }
        let cfg = config
        guard cfg.scrollUpAction != .none || cfg.scrollDownAction != .none else {
            lock.unlock()
            return false // wheel not bound: let it scroll as normal
        }
        usedScroll = true
        // Classic wheels report whole ±1 notches; continuous devices report
        // fractions. Accumulate to one action per notch-worth either way.
        scrollAccumulator += Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        var steps = 0
        while scrollAccumulator >= 1 { scrollAccumulator -= 1; steps += 1 }
        while scrollAccumulator <= -1 { scrollAccumulator += 1; steps -= 1 }
        lock.unlock()

        if steps != 0 {
            // Scroll up is a positive delta.
            let action = steps > 0 ? cfg.scrollUpAction : cfg.scrollDownAction
            guard action != .none else { return true }
            for _ in 0..<abs(steps) {
                queue.async {
                    GestureCoordinator.shared.performDiscrete(
                        action: action, appPath: "", shellCommand: "")
                }
            }
        }
        return true
    }

    // MARK: - Click replay

    private static func postKeyTap(keyCode: Int, flags: CGEventFlags) {
        for down in [true, false] {
            guard let tap = CGEvent(keyboardEventSource: nil,
                                    virtualKey: CGKeyCode(keyCode),
                                    keyDown: down) else { continue }
            tap.flags = flags
            tap.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
            tap.post(tap: .cghidEventTap)
        }
    }

    private static func postClick(button: Int, at location: CGPoint) {
        let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .center
        let downType: CGEventType = button == 1 ? .rightMouseDown : .otherMouseDown
        let upType: CGEventType = button == 1 ? .rightMouseUp : .otherMouseUp
        for type in [downType, upType] {
            guard let click = CGEvent(mouseEventSource: nil, mouseType: type,
                                      mouseCursorPosition: location,
                                      mouseButton: mouseButton) else { continue }
            click.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
            click.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
            click.post(tap: .cghidEventTap)
        }
    }
}
