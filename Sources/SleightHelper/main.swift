import Foundation
import IOKit.pwr_mgt

/// sleight-helper — root launchd daemon.
///
/// Sleight cannot run an automation while the Mac is asleep. Setting the
/// keyboard backlight, the volume or the display brightness is a driver call,
/// and a sleeping Mac has no running process to make it; there is no way to
/// leave an instruction with the hardware to be carried out later. The only
/// way to hit an exact time is to have macOS wake the machine for it.
///
/// Booking a wake needs root: `IOPMSchedulePowerEvent` returns
/// kIOReturnNotPrivileged (-536870207) to an ordinary app, and `pmset` refuses
/// outright. That single privileged call is all this daemon exists for. It
/// reads the times Sleight wants to be awake for, books the earliest one, and
/// books the next one after each wake. It performs no automations itself and
/// touches nothing else on the system.

let ownerName = "com.kamenlevi.sleight"
let configPath = "/Library/Application Support/Sleight/wake-schedule.json"

// MARK: - What the app asks for

/// Written by Sleight, read here. Deliberately a much smaller thing than the
/// app's own config: times and days, nothing about what the automations do.
struct WakeSchedule: Codable {
    struct Rule: Codable {
        var hour: Int
        var minute: Int
        /// Calendar weekday numbers, 1 = Sunday … 7 = Saturday.
        var weekdays: [Int]
    }

    var enabled: Bool
    /// How far ahead of the automation to wake, so the app is running and
    /// settled by the time the job is actually due.
    var leadSeconds: Int
    var rules: [Rule]

    static func load() -> WakeSchedule? {
        guard let data = FileManager.default.contents(atPath: configPath) else { return nil }
        return try? JSONDecoder().decode(WakeSchedule.self, from: data)
    }
}

// MARK: - Logging

let stamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

func log(_ message: String) {
    print("\(stamp.string(from: Date())) \(message)")
    fflush(stdout)
}

// MARK: - Power events

/// Every wake this daemon has booked and not yet seen happen.
func ourScheduledEvents() -> [(date: Date, type: String)] {
    guard let raw = IOPMCopyScheduledPowerEvents()?.takeRetainedValue() as? [[String: Any]]
    else { return [] }
    return raw.compactMap { event in
        guard event[kIOPMPowerEventAppNameKey] as? String == ownerName,
              let date = event[kIOPMPowerEventTimeKey] as? Date,
              let type = event[kIOPMPowerEventTypeKey] as? String
        else { return nil }
        return (date, type)
    }
}

func cancelOurEvents() {
    for event in ourScheduledEvents() {
        IOPMCancelScheduledPowerEvent(event.date as CFDate,
                                      ownerName as CFString,
                                      event.type as CFString)
    }
}

/// The next time this rule comes round, at or after `now`.
func nextOccurrence(of rule: WakeSchedule.Rule, after now: Date,
                    calendar: Calendar) -> Date? {
    let target = DateComponents(hour: rule.hour, minute: rule.minute)
    var cursor = now
    // At most one week: a rule that matches no weekday matches nothing.
    for _ in 0..<8 {
        guard let candidate = calendar.nextDate(after: cursor, matching: target,
                                                matchingPolicy: .nextTime) else { return nil }
        if rule.weekdays.contains(calendar.component(.weekday, from: candidate)) {
            return candidate
        }
        cursor = candidate
    }
    return nil
}

/// Book a wake for the soonest automation, replacing whatever was booked
/// before. Only one event is ever outstanding: after the Mac wakes, the timer
/// below runs again and books the one after it.
func rearm() {
    guard let schedule = WakeSchedule.load() else {
        cancelOurEvents()
        log("no schedule file — nothing booked")
        return
    }
    guard schedule.enabled, !schedule.rules.isEmpty else {
        cancelOurEvents()
        log("waking disabled — nothing booked")
        return
    }

    let calendar = Calendar.current
    let now = Date()
    let lead = TimeInterval(max(0, schedule.leadSeconds))
    guard let due = schedule.rules
        .compactMap({ nextOccurrence(of: $0, after: now, calendar: calendar) })
        .min()
    else {
        cancelOurEvents()
        log("no upcoming occurrences — nothing booked")
        return
    }

    // Waking early gives the app time to be running when the job is due, but
    // never wake in the past.
    let wakeAt = max(due.addingTimeInterval(-lead), now.addingTimeInterval(5))

    // Already booked for this moment: leave it be rather than churning the
    // queue every time the timer comes round.
    if ourScheduledEvents().contains(where: { abs($0.date.timeIntervalSince(wakeAt)) < 1 }) {
        return
    }

    cancelOurEvents()
    let result = IOPMSchedulePowerEvent(wakeAt as CFDate, ownerName as CFString,
                                        kIOPMAutoWake as CFString)
    if result == kIOReturnSuccess {
        log("booked wake at \(stamp.string(from: wakeAt)) for automation due \(stamp.string(from: due))")
    } else {
        log("could not book wake at \(stamp.string(from: wakeAt)): IOKit error \(result)")
    }
}

// MARK: - Flags

if CommandLine.arguments.contains("--clear") {
    cancelOurEvents()
    log("cleared all booked wakes")
    exit(0)
}

/// Round-trips a real wake booking, so an install can be checked without
/// waiting for the morning.
if CommandLine.arguments.contains("--probe") {
    let when = Date().addingTimeInterval(600)
    let result = IOPMSchedulePowerEvent(when as CFDate, ownerName as CFString,
                                        kIOPMAutoWake as CFString)
    print("uid=\(getuid()) IOPMSchedulePowerEvent -> \(result) (0 = success)")
    if result == kIOReturnSuccess {
        print("booked: \(ourScheduledEvents().map { stamp.string(from: $0.date) })")
        IOPMCancelScheduledPowerEvent(when as CFDate, ownerName as CFString,
                                      kIOPMAutoWake as CFString)
        print("cancelled again — scheduling works")
    } else {
        print("scheduling denied at this privilege level")
    }
    exit(result == kIOReturnSuccess ? 0 : 1)
}

// MARK: - Daemon

log("sleight-helper starting (uid \(getuid()))")
rearm()

// Sleight rewrites the schedule whenever the automations change.
var watcher: DispatchSourceFileSystemObject?
func watchConfig() {
    watcher?.cancel()
    let descriptor = open(configPath, O_EVTONLY)
    guard descriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend], queue: .main)
    source.setEventHandler {
        rearm()
        // Atomic writes replace the file, so the old descriptor is now stale.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { watchConfig() }
    }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    watcher = source
}
watchConfig()

// Belt and braces: catches the file appearing for the first time, re-arms
// after each wake, and recovers if a booking was ever lost.
let timer = Timer(timeInterval: 300, repeats: true) { _ in
    watchConfig()
    rearm()
}
timer.tolerance = 60
RunLoop.main.add(timer, forMode: .common)

// Held for the process lifetime: a signal source that goes out of scope stops
// listening, and launchd's SIGTERM would kill us without a word in the log.
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        log("stopping — leaving booked wakes in place")
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

RunLoop.main.run()
