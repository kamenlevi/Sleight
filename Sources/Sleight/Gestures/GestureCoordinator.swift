import AppKit
import Foundation

/// Coalesces high-frequency value writes down to ~45 Hz with leading +
/// trailing edges. DisplayServices and CoreBrightness setters are XPC calls
/// that take milliseconds; calling them at the trackpad's 125 Hz frame rate
/// backs up the gesture queue and made dials feel rigid.
final class CoalescedWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Float?
    private var scheduled = false
    private let interval: Double
    private let queue: DispatchQueue
    private let write: (Float) -> Void

    init(label: String, interval: Double = 1.0 / 45.0, write: @escaping (Float) -> Void) {
        self.interval = interval
        self.queue = DispatchQueue(label: label, qos: .userInteractive)
        self.write = write
    }

    func submit(_ value: Float) {
        lock.lock()
        if scheduled {
            pending = value
            lock.unlock()
            return
        }
        scheduled = true
        lock.unlock()
        queue.async { [self] in
            write(value)
            queue.asyncAfter(deadline: .now() + interval) { self.flush() }
        }
    }

    private func flush() {
        lock.lock()
        guard let value = pending else {
            scheduled = false
            lock.unlock()
            return
        }
        pending = nil
        lock.unlock()
        write(value)
        queue.asyncAfter(deadline: .now() + interval) { self.flush() }
    }
}

/// Hub between the touch stream, per-device gesture engines, system actions,
/// and UI feedback. Gesture callbacks arrive on the touch queue; everything
/// UI-facing hops to the main actor.
final class GestureCoordinator: @unchecked Sendable {
    static let shared = GestureCoordinator()

    private struct AdjustmentSession {
        let control: ContinuousControl
        var value: Float
        var lastDetent: Float
        let available: Bool
        let deviceID: UInt
    }

    private var engines: [UInt: GestureEngine] = [:]
    private var config = SleightConfig()
    private var session: AdjustmentSession?
    private var lastHUDPush: Double = 0

    private let displayWriter = CoalescedWriter(label: "com.kamenlevi.sleight.display") {
        DisplayBrightness.set($0)
    }
    private let keyboardWriter = CoalescedWriter(label: "com.kamenlevi.sleight.keyboard") {
        KeyboardBacklight.shared.set($0)
    }

    /// Set by the visualizer while its window is visible.
    var visualizerSink: (@Sendable (TouchFrame) -> Void)?
    private var lastVisualizerPush: Double = 0

    private init() {}

    func start(initialConfig: SleightConfig) {
        config = initialConfig
        TouchStream.shared.onFrame = { [weak self] frame in
            self?.handle(frame)
        }
        TouchStream.shared.start()
    }

    func handle(_ frame: TouchFrame) {
        if visualizerSink != nil, frame.timestamp - lastVisualizerPush > 1.0 / 60.0 || frame.touches.isEmpty {
            lastVisualizerPush = frame.timestamp
            visualizerSink?(frame)
        }

        let engine: GestureEngine
        if let existing = engines[frame.deviceID] {
            engine = existing
        } else {
            engine = GestureEngine(deviceID: frame.deviceID, coordinator: self)
            engine.config = config
            engines[frame.deviceID] = engine
        }
        engine.process(frame)
    }

    /// Called on the main actor by ConfigStore; engines read config at frame
    /// granularity so plain assignment is fine.
    func configChanged(_ newConfig: SleightConfig) {
        config = newConfig
        for engine in engines.values {
            engine.config = newConfig
        }
    }

    // MARK: - Continuous gestures

    func gestureBegan(control: ContinuousControl, deviceID: UInt) {
        let current: Float?
        switch control {
        case .volume:
            SystemVolume.refreshDevice()
            if SystemVolume.isMuted() == true {
                SystemVolume.setMuted(false)
            }
            current = SystemVolume.get()
        case .displayBrightness:
            current = DisplayBrightness.get()
        case .keyboardBrightness:
            current = KeyboardBacklight.shared.get()
        case .none:
            current = nil
        }
        let value = current ?? 0
        session = AdjustmentSession(
            control: control,
            value: value,
            lastDetent: value,
            available: current != nil,
            deviceID: deviceID
        )
        EventSuppressor.shared.setSuppressing(true)
        if config.showHUD {
            let available = current != nil
            Task { @MainActor in
                HUDController.shared.show(control: control, value: value, available: available)
            }
        }
    }

    func gestureChanged(delta: Float) {
        guard var current = session, current.available else { return }
        current.value = min(max(current.value + delta, 0), 1)

        switch current.control {
        case .volume: SystemVolume.set(current.value)
        case .displayBrightness: displayWriter.submit(current.value)
        case .keyboardBrightness: keyboardWriter.submit(current.value)
        case .none: break
        }

        let detentSize: Float = 0.05
        if config.hapticDetents, abs(current.value - current.lastDetent) >= detentSize,
           current.value > 0, current.value < 1 {
            current.lastDetent = current.value
            HapticEngine.shared.click(deviceID: current.deviceID)
        }

        session = current
        if config.showHUD {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastHUDPush > 1.0 / 60.0 {
                lastHUDPush = now
                let control = current.control
                let value = current.value
                Task { @MainActor in
                    HUDController.shared.update(control: control, value: value)
                }
            }
        }
    }

    /// A finger lifted mid-gesture but at least one is still down: keep the
    /// session so the gesture resumes when the finger returns, but let
    /// scrolling through again in the meantime.
    func gestureSuspended() {
        EventSuppressor.shared.setSuppressing(false)
        Task { @MainActor in
            HUDController.shared.scheduleHide(after: 1.5)
        }
    }

    func gestureResumed() {
        guard let current = session else { return }
        EventSuppressor.shared.setSuppressing(true)
        if config.showHUD {
            let control = current.control
            let value = current.value
            let available = current.available
            Task { @MainActor in
                HUDController.shared.show(control: control, value: value, available: available)
            }
        }
    }

    func gestureEnded() {
        session = nil
        EventSuppressor.shared.setSuppressing(false)
        Task { @MainActor in
            HUDController.shared.scheduleHide()
        }
    }

    // MARK: - Discrete gestures

    func tapDetected(fingerCount: Int) {
        let tapConfig: TapConfig
        switch fingerCount {
        case 3: tapConfig = config.threeFingerTap
        case 4: tapConfig = config.fourFingerTap
        case 5: tapConfig = config.fiveFingerTap
        default: return
        }
        perform(tapConfig)
    }

    private func perform(_ tap: TapConfig) {
        switch tap.action {
        case .none:
            break
        case .playPause:
            Task { @MainActor in MediaKeys.press(MediaKeys.playPause) }
        case .nextTrack:
            Task { @MainActor in MediaKeys.press(MediaKeys.next) }
        case .previousTrack:
            Task { @MainActor in MediaKeys.press(MediaKeys.previous) }
        case .muteToggle:
            let muted = SystemVolume.isMuted() ?? false
            SystemVolume.setMuted(!muted)
            let nowMuted = !muted
            if config.showHUD {
                let volume = SystemVolume.get() ?? 0
                Task { @MainActor in
                    HUDController.shared.show(
                        control: .volume,
                        value: nowMuted ? 0 : volume,
                        available: true,
                        muted: nowMuted
                    )
                    HUDController.shared.scheduleHide()
                }
            }
        case .launchApp:
            let path = tap.appPath
            guard !path.isEmpty else { return }
            Task { @MainActor in
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: path),
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
        case .shellCommand:
            let command = tap.shellCommand
            guard !command.isEmpty else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            try? process.run()
        }
    }
}
