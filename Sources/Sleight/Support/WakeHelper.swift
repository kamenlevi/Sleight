import AppKit
import Foundation

/// Installs and feeds the root daemon that wakes the Mac for automations.
///
/// Everything Sleight does to run an automation — set the backlight, the
/// volume, the brightness — is a call made by a running process. A sleeping
/// Mac has none, and nothing can be left with the hardware to carry out later,
/// so the only way to hit an exact time is for macOS to wake the machine. That
/// booking is root-only (`IOPMSchedulePowerEvent` refuses an ordinary app), so
/// it lives in a tiny separate daemon; see Sources/SleightHelper.
///
/// Without the helper, automations still run — at the first wake after they
/// come due, which on an idle Mac is usually within a quarter of an hour.
@MainActor
@Observable
final class WakeHelper {
    static let shared = WakeHelper()

    static let label = "com.kamenlevi.sleight.helper"
    static let binaryPath = "/Library/PrivilegedHelperTools/\(label)"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    static let configDirectory = "/Library/Application Support/Sleight"
    static let schedulePath = "\(configDirectory)/wake-schedule.json"

    /// Wake this long before the automation is due, so the app is up and
    /// running by the time the job's minute actually arrives.
    private static let leadSeconds = 45

    private(set) var isInstalled = false
    var lastError: String?
    /// True while an install or removal is waiting on the password prompt.
    private(set) var busy = false

    private init() {
        refresh()
    }

    func refresh() {
        let fileManager = FileManager.default
        isInstalled = fileManager.fileExists(atPath: Self.binaryPath)
            && fileManager.fileExists(atPath: Self.plistPath)
    }

    func install() {
        runPrivilegedScript(named: "install-helper.sh") { [weak self] success in
            guard let self else { return }
            refresh()
            if success { writeSchedule(ConfigStore.shared.config) }
        }
    }

    func uninstall() {
        runPrivilegedScript(named: "uninstall-helper.sh") { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Feeding the daemon

    /// Called whenever the config changes. Only the times matter to the
    /// helper, so anything else changing is ignored.
    func configChanged(_ config: SleightConfig) {
        guard isInstalled else { return }
        let wanted = Self.rules(from: config)
        guard wanted != lastWrittenRules || config.enabled != lastWrittenEnabled else { return }
        writeSchedule(config)
    }

    private var lastWrittenRules: [Rule] = []
    private var lastWrittenEnabled = true

    private struct Rule: Codable, Equatable {
        var hour: Int
        var minute: Int
        var weekdays: [Int]
    }

    private struct Schedule: Codable {
        var enabled: Bool
        var leadSeconds: Int
        var rules: [Rule]
    }

    private static func rules(from config: SleightConfig) -> [Rule] {
        config.automations
            .filter(\.enabled)
            .map { Rule(hour: $0.hour, minute: $0.minute, weekdays: $0.weekdays.sorted()) }
    }

    func writeSchedule(_ config: SleightConfig) {
        guard isInstalled else { return }
        let rules = Self.rules(from: config)
        let schedule = Schedule(enabled: config.enabled, leadSeconds: Self.leadSeconds, rules: rules)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(schedule).write(to: URL(fileURLWithPath: Self.schedulePath),
                                               options: .atomic)
            lastWrittenRules = rules
            lastWrittenEnabled = config.enabled
            lastError = nil
            SleightLog.log("wake helper: wrote \(rules.count) time(s) for it to wake for")
        } catch {
            lastError = "Could not update the wake schedule: \(error.localizedDescription)"
        }
    }

    // MARK: - Privileged install

    /// Runs a bundled script as root behind the system's admin-password
    /// prompt. Only ever used to install or remove the daemon — never to run
    /// an automation.
    private func runPrivilegedScript(named scriptName: String,
                                     completion: @escaping @MainActor (Bool) -> Void) {
        guard let scriptPath = Bundle.main.path(forResource: scriptName, ofType: nil),
              let resourcePath = Bundle.main.resourcePath else {
            lastError = "Helper files are missing — this needs the built Sleight.app, not a bare binary."
            completion(false)
            return
        }
        busy = true
        let command = [scriptPath, resourcePath, NSUserName()]
            .map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
            .joined(separator: " ")
        let escaped = "/bin/bash \(command)"
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
            let message = errorInfo?[NSAppleScript.errorMessage] as? String
            let code = errorInfo?[NSAppleScript.errorNumber] as? Int
            Task { @MainActor in
                self.busy = false
                if result == nil {
                    // -128 is the user cancelling the password prompt.
                    self.lastError = code == -128 ? nil : (message ?? "The helper script failed.")
                    SleightLog.log("wake helper: \(scriptName) failed — \(message ?? "cancelled")")
                    completion(false)
                } else {
                    self.lastError = nil
                    SleightLog.log("wake helper: \(scriptName) succeeded")
                    completion(true)
                }
            }
        }
    }
}
