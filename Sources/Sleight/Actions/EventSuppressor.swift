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

    private let lock = NSLock()
    private var level: Level = .off
    private var pointerFrozen = false
    private var swallowMomentumUntil: Double = 0

    private var tap: CFMachPort?

    private init() {}

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
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
