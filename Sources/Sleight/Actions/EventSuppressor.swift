import AppKit
import CoreGraphics

/// While a gesture is forming or active, macOS would still interpret the
/// same fingers as scrolling or a back/forward swipe. This event tap
/// swallows scroll-wheel and gesture events for the duration (plus the
/// momentum tail), and can optionally pin the pointer. Blocking happens at
/// the input layer — pages never see the events, but nothing is paused, so
/// videos keep playing.
///
/// Levels are set from the touch queue and read on the event tap thread;
/// the lock keeps them coherent. `start` must be called on the main thread.
final class EventSuppressor: @unchecked Sendable {
    static let shared = EventSuppressor()

    enum Level {
        case off
        /// Swallow scroll/swipe input while a candidate gesture forms.
        case scrollOnly
        /// A gesture is active: swallow scroll/swipe input.
        case gesture
    }

    struct ResolvedShortcut {
        let id: UUID
        let keyCode: Int
        let modifiers: Int
    }

    private let lock = NSLock()
    private var level: Level = .off
    private var pointerFrozen = false
    private var swallowMomentumUntil: Double = 0
    private var shortcuts: [ResolvedShortcut] = []

    /// Fired (off the tap thread) when a registered shortcut is pressed.
    var onShortcut: (@Sendable (UUID) -> Void)?

    private var tap: CFMachPort?

    private init() {}

    func updateShortcuts(_ newShortcuts: [ResolvedShortcut]) {
        lock.lock()
        shortcuts = newShortcuts
        lock.unlock()
    }

    // While set (during shortcut recording), the next real keyDown is
    // captured and swallowed instead of matched. Because this runs on the
    // session tap, it catches far more combinations than a per-app monitor,
    // including ones macOS would otherwise consume first.
    private var recordingCapture: (@Sendable (Int, Int) -> Void)?

    var canCaptureRecording: Bool { tap != nil }

    func beginRecordingCapture(_ handler: @escaping @Sendable (Int, Int) -> Void) {
        lock.lock()
        recordingCapture = handler
        lock.unlock()
    }

    func endRecordingCapture() {
        lock.lock()
        recordingCapture = nil
        lock.unlock()
    }

    /// Returns true if a recording capture consumed this keyDown.
    private func handleRecording(_ event: CGEvent) -> Bool {
        lock.lock()
        let capture = recordingCapture
        lock.unlock()
        guard let capture else { return false }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        // Ignore standalone modifier keys and key-repeats.
        let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeyCodes.contains(keyCode) { return true }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }

        let modifiers = Keystrokes.canonical(event.flags, keyCode: keyCode)
        lock.lock()
        recordingCapture = nil
        lock.unlock()
        DispatchQueue.main.async { capture(keyCode, modifiers) }
        return true
    }

    /// Returns true when the key event belongs to a registered shortcut and
    /// must be swallowed. Fires the action on the initial press (not repeats).
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        lock.lock()
        let current = shortcuts
        lock.unlock()
        guard !current.isEmpty else { return false }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = Keystrokes.canonical(event.flags, keyCode: keyCode)
        guard let match = current.first(where: { $0.keyCode == keyCode && $0.modifiers == modifiers }) else {
            return false
        }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0, let onShortcut {
            let id = match.id
            SleightLog.log("shortcut fired via event tap (keyCode \(keyCode))")
            DispatchQueue.global(qos: .userInteractive).async {
                onShortcut(id)
            }
        }
        return true
    }

    func setLevel(_ newLevel: Level) {
        lock.lock()
        if newLevel == .off, level != .off {
            // Fingers just lifted; momentum scroll events may still arrive.
            swallowMomentumUntil = CFAbsoluteTimeGetCurrent() + 0.5
        }
        level = newLevel
        lock.unlock()
    }

    func setPointerFrozen(_ frozen: Bool) {
        lock.lock()
        pointerFrozen = frozen
        lock.unlock()
    }

    /// Scroll wheel, the undocumented gesture/dock-gesture types (29/30:
    /// pinch, rotate, swipe navigation), and pointer movement.
    private func isInteresting(_ type: CGEventType) -> Bool {
        switch type {
        case .scrollWheel, .mouseMoved,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return type.rawValue == 29 || type.rawValue == 30
        }
    }

    private func shouldSwallow(_ event: CGEvent, type: CGEventType) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if type == .mouseMoved || type == .leftMouseDragged
            || type == .rightMouseDragged || type == .otherMouseDragged {
            return pointerFrozen
        }
        if level != .off { return true }
        if type == .scrollWheel, CFAbsoluteTimeGetCurrent() < swallowMomentumUntil {
            let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            return momentum != 0
        }
        return false
    }

    private func reenable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        // Listen to ALL events and filter inside the callback. Requesting
        // the undocumented gesture event types (29/30) in the creation mask
        // can make tapCreate silently fail on some macOS versions — which
        // would disable suppression entirely. The catch-all mask cannot fail
        // that way; the callback below is trivial for uninteresting events.
        let mask = CGEventMask.max

        let callback: CGEventTapCallBack = { _, type, event, _ in
            let suppressor = EventSuppressor.shared
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                suppressor.reenable()
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown, suppressor.handleRecording(event) {
                return nil
            }
            if type == .keyDown, suppressor.handleKeyDown(event) {
                return nil
            }
            if suppressor.isInteresting(type), suppressor.shouldSwallow(event, type: type) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            SleightLog.log("event tap creation FAILED (Accessibility not effective)")
            return
        }
        SleightLog.log("event tap created")

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
