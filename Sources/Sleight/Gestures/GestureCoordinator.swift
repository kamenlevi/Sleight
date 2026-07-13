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
        EventSuppressor.shared.onShortcut = { [weak self] id in
            self?.shortcutPressed(id)
        }
        HotkeyCenter.shared.onHotkey = { [weak self] id in
            self?.shortcutPressed(id)
        }
        pushShortcuts()
        TouchStream.shared.start()
    }

    /// Every shortcut is armed on BOTH paths: Carbon hotkeys (no permissions
    /// needed, but can't express Globe combos) and the event tap (needs
    /// Accessibility, sees everything). Whichever fires first wins;
    /// duplicates within the dedupe window are dropped.
    private func pushShortcuts() {
        lastPushedShortcuts = config.shortcuts
        let active = config.shortcuts.filter { $0.enabled && $0.isRecorded && $0.action != .none }

        EventSuppressor.shared.updateShortcuts(active.map {
            EventSuppressor.ResolvedShortcut(id: $0.id, keyCode: $0.keyCode, modifiers: $0.modifiers)
        })
        let entries = active
            .filter { $0.modifiers & Keystrokes.fn == 0 }
            .map { HotkeyCenter.Entry(id: $0.id, keyCode: $0.keyCode, modifiers: $0.modifiers) }
        if Thread.isMainThread {
            HotkeyCenter.shared.update(entries)
        } else {
            DispatchQueue.main.async {
                HotkeyCenter.shared.update(entries)
            }
        }
    }

    private var lastShortcutFire: [UUID: Double] = [:]

    private func shortcutPressed(_ id: UUID) {
        let now = CFAbsoluteTimeGetCurrent()
        if let last = lastShortcutFire[id], now - last < 0.15 {
            return // the other path already handled this press
        }
        lastShortcutFire[id] = now
        guard config.enabled,
              let binding = config.shortcuts.first(where: { $0.id == id }) else {
            SleightLog.log("shortcut fired but no matching enabled binding (id \(id))")
            return
        }
        SleightLog.log("shortcut executing action \(binding.action.rawValue)")
        performDiscrete(action: binding.action, appPath: binding.appPath, shellCommand: binding.shellCommand, targetApp: binding.targetApp)
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
    private var lastPushedShortcuts: [ShortcutBinding] = []

    func configChanged(_ newConfig: SleightConfig) {
        config = newConfig
        for engine in engines.values {
            engine.config = newConfig
        }
        // Re-registering hotkeys is main-thread Carbon work; skip it unless
        // the shortcuts themselves changed (config mutates on every slider
        // tick in settings).
        if newConfig.shortcuts != lastPushedShortcuts {
            pushShortcuts()
        }
    }

    // MARK: - Continuous gestures

    /// A landing posture or early motion looks like a gesture: freeze
    /// scrolling immediately so the page can't move or navigate while the
    /// gesture finishes forming. Cleared by the engine if it was a scroll.
    func candidateFreezeChanged(_ frozen: Bool) {
        guard session == nil else { return } // active gesture owns suppression
        EventSuppressor.shared.setLevel(frozen && config.freezeScreen ? .scrollOnly : .off)
    }

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
        EventSuppressor.shared.setLevel(.gesture)
        EventSuppressor.shared.setPointerFrozen(config.freezePointer)
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
        EventSuppressor.shared.setLevel(.off)
        EventSuppressor.shared.setPointerFrozen(false)
        Task { @MainActor in
            HUDController.shared.scheduleHide(after: 1.5)
        }
    }

    func gestureResumed() {
        guard let current = session else { return }
        EventSuppressor.shared.setLevel(.gesture)
        EventSuppressor.shared.setPointerFrozen(config.freezePointer)
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
        EventSuppressor.shared.setLevel(.off)
        EventSuppressor.shared.setPointerFrozen(false)
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
        performDiscrete(action: tapConfig.action, appPath: tapConfig.appPath, shellCommand: tapConfig.shellCommand, targetApp: tapConfig.targetApp)
    }

    /// A brief HUD confirmation for actions whose effect isn't otherwise
    /// visible. Strictly opt-in (Settings → General → Feedback): by default
    /// actions run silently, with nothing to distract from what you're doing.
    private func flash(_ symbol: String, _ text: String) {
        guard config.showHUD, config.actionConfirmations else { return }
        Task { @MainActor in HUDController.shared.flash(symbol: symbol, text: text) }
    }

    /// The level HUD (same bezel as the dials), used by the step actions.
    private func showLevel(_ control: ContinuousControl, _ value: Float) {
        guard config.showHUD else { return }
        Task { @MainActor in
            HUDController.shared.show(control: control, value: value, available: true)
            HUDController.shared.scheduleHide()
        }
    }

    func performDiscrete(action: DiscreteAction, appPath: String, shellCommand: String,
                         targetApp: String? = nil) {
        // A target only applies where it means something.
        let target = action.supportsAppTarget ? targetApp.flatMap { $0.isEmpty ? nil : $0 } : nil
        let targetName = target.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
        switch action {
        case .none:
            break
        case .playPause:
            if let target {
                SystemActions.mediaCommand(SystemActions.playPauseVariants, appPath: target)
            } else {
                Task { @MainActor in MediaKeys.press(MediaKeys.playPause) }
            }
            flash(action.symbol, targetName.map { "Play / Pause — \($0)" } ?? "Play / Pause")
        case .nextTrack:
            if let target {
                SystemActions.mediaCommand(SystemActions.nextTrackVariants, appPath: target)
            } else {
                Task { @MainActor in MediaKeys.press(MediaKeys.next) }
            }
            flash(action.symbol, targetName.map { "Next Track — \($0)" } ?? "Next Track")
        case .previousTrack:
            if let target {
                SystemActions.mediaCommand(SystemActions.previousTrackVariants, appPath: target)
            } else {
                Task { @MainActor in MediaKeys.press(MediaKeys.previous) }
            }
            flash(action.symbol, targetName.map { "Previous Track — \($0)" } ?? "Previous Track")
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
        case .keyboardBrightnessCycle:
            // Actual hardware levels, user-editable; disabled ones are skipped.
            var states = Set(config.keyboardLevels
                .filter { $0.enabled }
                .map { Float(min(max($0.value, 0), 1)) }).sorted()
            if states.count < 2 { states = [0, 1] }
            let reading = KeyboardBacklight.shared.get()
            SleightLog.log("cycle backlight: current=\(reading == nil ? "nil" : "\(reading!)") levels=\(states)")
            guard let current = reading else {
                if config.showHUD {
                    Task { @MainActor in
                        HUDController.shared.show(control: .keyboardBrightness, value: 0, available: false)
                        HUDController.shared.scheduleHide()
                    }
                }
                return
            }
            // Jump to whichever level comes after the nearest one.
            let nearest = states.enumerated().min {
                abs($0.element - current) < abs($1.element - current)
            }!.offset
            let next = states[(nearest + 1) % states.count]
            KeyboardBacklight.shared.set(next)
            if config.showHUD {
                Task { @MainActor in
                    HUDController.shared.show(control: .keyboardBrightness, value: next, available: true)
                    HUDController.shared.scheduleHide()
                }
            }
        case .launchApp:
            let path = appPath
            guard !path.isEmpty else { return }
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            flash(action.symbol, "Opening \(name)")
            Task { @MainActor in
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: path),
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
        case .shellCommand:
            let command = shellCommand
            guard !command.isEmpty else { return }
            flash(action.symbol, "Ran: \(command)")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            try? process.run()
        case .cycleInputSource:
            Task { @MainActor in
                let name = SystemActions.cycleInputSource()
                self.flash("globe", name.map { "Keyboard: \($0)" }
                    ?? "Only one keyboard language is enabled")
            }
        case .micMuteToggle:
            if let muted = SystemActions.toggleMicMute() {
                flash(muted ? "mic.slash.fill" : "mic.fill",
                      muted ? "Microphone muted" : "Microphone live")
            } else {
                flash("mic.badge.xmark", "This microphone has no mute control")
            }
        case .volumeUp, .volumeDown:
            let current = SystemVolume.get() ?? 0
            let next = min(1, max(0, current + (action == .volumeUp ? 1 : -1) * Float(1.0 / 16)))
            SystemVolume.set(next)
            showLevel(.volume, next)
        case .displayBrightnessUp, .displayBrightnessDown:
            let current = DisplayBrightness.get() ?? 0
            let next = min(1, max(0, current + (action == .displayBrightnessUp ? 1 : -1) * Float(1.0 / 16)))
            DisplayBrightness.set(next)
            showLevel(.displayBrightness, next)
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            let current = KeyboardBacklight.shared.get() ?? 0
            let next = min(1, max(0, current + (action == .keyboardBrightnessUp ? 1 : -1) * Float(0.1)))
            KeyboardBacklight.shared.set(next)
            showLevel(.keyboardBrightness, next)
        case .sleepDisplays:
            SystemActions.sleepDisplays()
        case .sleepMac:
            SystemActions.sleepMac()
        case .startScreenSaver:
            SystemActions.startScreenSaver()
        case .missionControl:
            SystemActions.missionControl()
        case .toggleDarkMode:
            SystemActions.toggleDarkMode()
        case .screenshotArea:
            SystemActions.screenshotArea()
        case .screenshotScreen:
            SystemActions.screenshotScreen()
        case .emptyTrash:
            SystemActions.emptyTrash()
        case .lockScreen, .showDesktop, .appExpose, .spaceLeft, .spaceRight,
             .spotlight, .browserBack, .browserForward, .nextTab, .previousTab,
             .newTab, .reopenClosedTab, .closeTabOrWindow, .minimizeWindow,
             .hideApp, .fullScreenToggle, .zoomIn, .zoomOut:
            // The system's own keyboard shortcut, synthesized — into one
            // specific app's event queue when a target is set.
            _ = SystemActions.keystroke(for: action, toAppAt: target)
        }
    }
}
