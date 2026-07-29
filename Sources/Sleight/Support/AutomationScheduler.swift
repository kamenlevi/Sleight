import AppKit
import Foundation

/// Runs the user's scheduled automations.
///
/// The scheduler asks "did this job come due since I last looked?", not "is it
/// due this very minute". The difference matters enormously: timers don't run
/// while the Mac sleeps, and an idle Mac only dark-wakes for a couple of
/// seconds every quarter of an hour, so a scheduler needing a tick inside one
/// specific 60-second window would miss a 06:00 job on most nights — which is
/// exactly what it used to do. Now a time that passes while the Mac is asleep
/// runs at the first wake afterwards, as long as that's within `catchUpWindow`.
@MainActor
final class AutomationScheduler {
    static let shared = AutomationScheduler()

    private var timer: Timer?
    /// Occurrence each job last ran for, so a job can't run twice for the
    /// same scheduled time.
    private var lastFired: [UUID: Date] = [:]
    /// When the clock was last examined. Persisted, so a time that passes
    /// while Sleight isn't running is still caught on the next launch.
    private var lastCheck: Date
    private static let lastCheckKey = "com.kamenlevi.sleight.automationLastCheck"

    /// How late a missed job may still run. Long enough to cover a night's
    /// sleep, short enough that opening the lid in the evening doesn't set off
    /// something scheduled for breakfast.
    private let catchUpWindow: TimeInterval = 6 * 3600

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        // First ever run: start from now, so nothing fires retroactively.
        lastCheck = stored > 0 ? Date(timeIntervalSince1970: stored) : Date()
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { _ in
            Task { @MainActor in AutomationScheduler.shared.tick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Waking is the moment the missed jobs are waiting for — don't sit on
        // them for up to 20 seconds.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AutomationScheduler.shared.tick() }
        }

        tick()
    }

    private func tick() {
        let now = Date()
        defer {
            lastCheck = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastCheckKey)
        }

        let config = ConfigStore.shared.config
        guard config.enabled, !config.automations.isEmpty else { return }

        for job in config.automations where job.enabled {
            guard let due = mostRecentOccurrence(of: job, at: now) else { continue }
            // Already accounted for on an earlier pass.
            guard due > lastCheck, lastFired[job.id] != due else { continue }
            let late = now.timeIntervalSince(due)
            guard late <= catchUpWindow else {
                SleightLog.log("automation: skipping \(job.summary) — \(Int(late / 60))m late, past the catch-up window")
                continue
            }
            lastFired[job.id] = due
            let lateness = late < 60 ? "" : " (\(Int(late / 60))m late)"
            SleightLog.log("automation: firing \(job.summary)\(lateness)")
            run(job)
        }
    }

    /// The last time this job was due at or before `now`, or nil if its most
    /// recent scheduled time falls on a weekday it isn't set to run.
    ///
    /// Only the single most recent match is considered: anything earlier is
    /// over a day old, and so past the catch-up window regardless.
    private func mostRecentOccurrence(of job: Automation, at now: Date) -> Date? {
        let calendar = Calendar.current
        guard let due = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: job.hour, minute: job.minute),
            matchingPolicy: .nextTime,
            direction: .backward
        ) else { return nil }
        let weekday = calendar.component(.weekday, from: due)
        return job.weekdays.contains(weekday) ? due : nil
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
