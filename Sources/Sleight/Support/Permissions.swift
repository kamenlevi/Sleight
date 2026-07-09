import AppKit
import ApplicationServices
import IOKit.hid

/// The two TCC grants Sleight needs: Input Monitoring for raw trackpad
/// touches, Accessibility for swallowing scroll events and posting media keys.
enum Permissions {
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// What IOHIDCheckAccess claims. Unreliable on its own — it reports
    /// denied even while touch frames are flowing — so prefer
    /// `inputMonitoringWorking` for anything user-facing.
    static var inputMonitoringReportedGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private static let rememberedKey = "com.kamenlevi.sleight.inputMonitoringConfirmed"

    /// True if Input Monitoring is actually functional: either the API says
    /// so, or we've received real touch data (proof it works), or we
    /// confirmed it on a previous run. Once confirmed it's remembered, so a
    /// transient API lie never demotes a working install.
    static var inputMonitoringWorking: Bool {
        if TouchStream.shared.hasReceivedTouchData {
            UserDefaults.standard.set(true, forKey: rememberedKey)
            return true
        }
        if inputMonitoringReportedGranted {
            UserDefaults.standard.set(true, forKey: rememberedKey)
            return true
        }
        return UserDefaults.standard.bool(forKey: rememberedKey)
    }

    static func requestInputMonitoring() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Deletes Sleight's TCC entries (they go stale when the app's signing
    /// identity changes) and immediately re-requests both permissions, so
    /// fresh prompts appear instead of a lying checkbox in System Settings.
    static func repair() {
        for service in ["Accessibility", "ListenEvent"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, "com.kamenlevi.sleight"]
            try? process.run()
            process.waitUntilExit()
        }
        UserDefaults.standard.removeObject(forKey: rememberedKey)
        SleightLog.log("permissions repaired via tccutil; re-requesting")
        requestInputMonitoring()
        requestAccessibility()
    }

    /// Relaunch the app. macOS often keeps reporting Accessibility as denied
    /// in a process that was already running when the grant was made; a
    /// relaunch makes the fresh grant take effect.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "sleep 0.5; open \"\(path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}
