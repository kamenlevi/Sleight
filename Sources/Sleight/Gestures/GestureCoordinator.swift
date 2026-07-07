import AppKit
import Foundation

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
    }

    private var engines: [UInt: GestureEngine] = [:]
    private var config = SleightConfig()
    private var session: AdjustmentSession?

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

    /// Called on the main actor by ConfigStore; hop onto the touch path
    /// by just assigning — engines read config at frame granularity.
    func configChanged(_ newConfig: SleightConfig) {
        config = newConfig
        for engine in engines.values {
            engine.config = newConfig
        }
    }

    // MARK: - Continuous gestures

    func gestureBegan(_ gesture: ContinuousGesture, config cfg: DialConfig) {
        let control = cfg.control
        let current: Float?
        switch control {
        case .volume: current = SystemVolume.get()
        case .displayBrightness: current = DisplayBrightness.get()
        case .keyboardBrightness: current = KeyboardBacklight.shared.get()
        case .none: current = nil
        }
        let value = current ?? 0
        session = AdjustmentSession(
            control: control,
            value: value,
            lastDetent: value,
            available: current != nil
        )
        EventSuppressor.shared.setSuppressing(true)
        if config.showHUD {
            let available = current != nil
            Task { @MainActor in
                HUDController.shared.show(control: control, value: value, available: available)
            }
        }
    }

    func gestureChanged(_ gesture: ContinuousGesture, delta: Float, config cfg: DialConfig) {
        guard var current = session, current.available else { return }
        current.value = min(max(current.value + delta, 0), 1)

        switch current.control {
        case .volume: SystemVolume.set(current.value)
        case .displayBrightness: DisplayBrightness.set(current.value)
        case .keyboardBrightness: KeyboardBacklight.shared.set(current.value)
        case .none: break
        }

        let detentSize: Float = 0.05
        if config.hapticDetents, abs(current.value - current.lastDetent) >= detentSize,
           current.value > 0, current.value < 1 {
            current.lastDetent = current.value
            Task { @MainActor in
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        }

        session = current
        if config.showHUD {
            let control = current.control
            let value = current.value
            Task { @MainActor in
                HUDController.shared.update(control: control, value: value)
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
