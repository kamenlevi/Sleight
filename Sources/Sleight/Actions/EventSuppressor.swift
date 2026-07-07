import AppKit
import CoreGraphics

/// While a dial or arc gesture is active, macOS would still interpret the
/// same fingers as scrolling. This event tap swallows scroll-wheel and
/// gesture events for the duration (plus the momentum tail) so turning the
/// volume knob never also scrolls the page underneath.
///
/// `setSuppressing` is called from the touch queue and `shouldSwallow` from
/// the event tap thread; the lock keeps them coherent. `start` must be
/// called on the main thread.
final class EventSuppressor: @unchecked Sendable {
    static let shared = EventSuppressor()

    private let lock = NSLock()
    private var active = false
    private var swallowMomentumUntil: Double = 0

    private var tap: CFMachPort?

    private init() {}

    func setSuppressing(_ on: Bool) {
        lock.lock()
        if !on, active {
            // Fingers just lifted; momentum scroll events may still arrive.
            swallowMomentumUntil = CFAbsoluteTimeGetCurrent() + 0.5
        }
        active = on
        lock.unlock()
    }

    private func shouldSwallow(_ event: CGEvent, type: CGEventType) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if active { return true }
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
        // 29 and 30 are the undocumented gesture / dock-gesture event types.
        let mask: CGEventMask =
            (1 << CGEventType.scrollWheel.rawValue) | (1 << 29) | (1 << 30)

        let callback: CGEventTapCallBack = { _, type, event, _ in
            let suppressor = EventSuppressor.shared
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                suppressor.reenable()
                return Unmanaged.passUnretained(event)
            }
            if suppressor.shouldSwallow(event, type: type) {
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
