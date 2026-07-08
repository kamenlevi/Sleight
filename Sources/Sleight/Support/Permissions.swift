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

    static var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
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
        SleightLog.log("permissions repaired via tccutil; re-requesting")
        requestInputMonitoring()
        requestAccessibility()
    }
}
