import AppKit

/// Haptic clicks straight through the trackpad's actuator (private
/// MultitouchSupport API). NSHapticFeedbackManager is the polite public
/// route, but macOS silently drops its requests unless it considers the app
/// to be handling a drag — which made detents feel intermittent. Driving the
/// actuator directly clicks every time, on the exact trackpad being touched.
final class HapticEngine: @unchecked Sendable {
    static let shared = HapticEngine()

    private let lock = NSLock()
    private var actuators: [UInt64: CFTypeRef] = [:]

    private init() {}

    /// Called from the gesture queue. `deviceID` is the pointer-bits ID that
    /// touch frames carry.
    func click(deviceID: UInt) {
        guard let hardwareID = TouchStream.shared.hardwareID(for: deviceID),
              let actuator = actuator(for: hardwareID),
              MultitouchBridge.actuate(actuator, actuationID: 4) else {
            fallback()
            return
        }
    }

    /// Drop open actuators when the device set changes (e.g. Bluetooth
    /// trackpad reconnected); they are lazily reopened on next use.
    func reset() {
        lock.lock()
        let old = actuators
        actuators = [:]
        lock.unlock()
        for actuator in old.values {
            MultitouchBridge.actuatorClose(actuator)
        }
    }

    private func actuator(for hardwareID: UInt64) -> CFTypeRef? {
        lock.lock()
        defer { lock.unlock() }
        if let existing = actuators[hardwareID] {
            return existing
        }
        guard let actuator = MultitouchBridge.actuatorCreate(hardwareID: hardwareID),
              MultitouchBridge.actuatorOpen(actuator) else {
            return nil
        }
        actuators[hardwareID] = actuator
        return actuator
    }

    private func fallback() {
        Task { @MainActor in
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
}
