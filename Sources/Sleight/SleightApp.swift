import SwiftUI

@main
struct SleightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = ConfigStore.shared

    var body: some Scene {
        MenuBarExtra {
            Toggle("Enabled", isOn: $store.config.enabled)
            Divider()
            Button("Settings…") {
                SettingsWindow.show()
            }
            .keyboardShortcut(",")
            Button("Trackpad Visualizer") {
                SettingsWindow.show(tab: .visualizer)
            }
            Divider()
            Button("Quit Sleight") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: store.config.enabled ? "dial.medium.fill" : "dial.medium")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var permissionPoll: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only even when running unbundled during development.
        NSApp.setActivationPolicy(.accessory)

        let firstLaunch = !UserDefaults.standard.bool(forKey: "com.kamenlevi.sleight.launchedBefore")
        UserDefaults.standard.set(true, forKey: "com.kamenlevi.sleight.launchedBefore")

        SleightLog.log("launch: accessibility=\(Permissions.accessibilityGranted) inputMonitoring=\(Permissions.inputMonitoringGranted) multitouch=\(MultitouchBridge.isAvailable)")

        if !Permissions.inputMonitoringGranted {
            Permissions.requestInputMonitoring()
        }
        if !Permissions.accessibilityGranted {
            Permissions.requestAccessibility()
        }

        GestureCoordinator.shared.start(initialConfig: ConfigStore.shared.config)
        if Permissions.accessibilityGranted {
            EventSuppressor.shared.start()
        }

        // Once permissions land, restart the touch stream (grants don't apply
        // retroactively to already-started devices) and bring up the tap.
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                var done = true
                if Permissions.accessibilityGranted {
                    if !EventSuppressor.shared.isRunning {
                        EventSuppressor.shared.start()
                        // Keep polling until the tap actually exists —
                        // creation can fail transiently right after a grant.
                        done = EventSuppressor.shared.isRunning
                    }
                } else {
                    done = false
                }
                if Permissions.inputMonitoringGranted {
                    if !TouchStream.shared.startedWithInputMonitoring {
                        TouchStream.shared.start()
                    }
                } else {
                    done = false
                }
                if done {
                    self?.permissionPoll?.invalidate()
                    self?.permissionPoll = nil
                }
            }
        }

        if firstLaunch || !Permissions.inputMonitoringGranted || !Permissions.accessibilityGranted {
            SettingsWindow.show(tab: .general)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        TouchStream.shared.stop()
    }
}
