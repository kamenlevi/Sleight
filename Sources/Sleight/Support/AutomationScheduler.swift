import AppKit
import Foundation

/// Runs the user's scheduled automations. A lightweight repeating timer
/// compares the wall clock against each enabled job once every 20 seconds;
/// a job fires at most once per calendar minute it matches. Times that pass
/// while the Mac is asleep are skipped, not replayed on wake.
@MainActor
final class AutomationScheduler {
    static let shared = AutomationScheduler()

    private var timer: Timer?
    /// Minute stamp each job last fired on, so the sub-minute tick can't
    /// fire the same job twice within its scheduled minute.
    private var lastFired: [UUID: String] = [:]

    private init() {}

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { _ in
            Task { @MainActor in AutomationScheduler.shared.tick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let config = ConfigStore.shared.config
        guard config.enabled, !config.automations.isEmpty else { return }
        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .weekday], from: Date())
        guard let hour = parts.hour, let minute = parts.minute, let weekday = parts.weekday else { return }
        let stamp = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0) \(hour):\(minute)"

        for job in config.automations where job.enabled {
            guard job.hour == hour, job.minute == minute,
                  job.weekdays.contains(weekday),
                  lastFired[job.id] != stamp else { continue }
            lastFired[job.id] = stamp
            SleightLog.log("automation: firing \(job.summary)")
            run(job)
        }
    }

    private func run(_ job: Automation) {
        let level = Float(min(max(job.level, 0), 1))
        switch job.action {
        case .setVolume:
            SystemVolume.refreshDevice()
            if SystemVolume.isMuted() == true { SystemVolume.setMuted(false) }
            SystemVolume.set(level)
            flashHUD(.volume, level)
        case .setDisplayBrightness:
            DisplayBrightness.set(level)
            flashHUD(.displayBrightness, level)
        case .setKeyboardBrightness:
            KeyboardBacklight.shared.set(level)
            flashHUD(.keyboardBrightness, level)
        case .mute:
            SystemVolume.setMuted(true)
        case .unmute:
            SystemVolume.setMuted(false)
        case .playPause:
            GestureCoordinator.shared.performDiscrete(action: .playPause, appPath: "", shellCommand: "", targetApp: job.targetApp)
        case .nextTrack:
            GestureCoordinator.shared.performDiscrete(action: .nextTrack, appPath: "", shellCommand: "", targetApp: job.targetApp)
        case .previousTrack:
            GestureCoordinator.shared.performDiscrete(action: .previousTrack, appPath: "", shellCommand: "", targetApp: job.targetApp)
        case .keyboardBrightnessCycle:
            GestureCoordinator.shared.performDiscrete(action: .keyboardBrightnessCycle, appPath: "", shellCommand: "")
        case .launchApp:
            GestureCoordinator.shared.performDiscrete(action: .launchApp, appPath: job.appPath, shellCommand: "")
        case .shellCommand:
            GestureCoordinator.shared.performDiscrete(action: .shellCommand, appPath: "", shellCommand: job.shellCommand)
        }
    }

    /// Brief HUD so a level change is visible if the user happens to be
    /// looking; respects the global HUD toggle.
    private func flashHUD(_ control: ContinuousControl, _ value: Float) {
        guard ConfigStore.shared.config.showHUD else { return }
        HUDController.shared.show(control: control, value: value, available: true)
        HUDController.shared.scheduleHide(after: 1.5)
    }
}
