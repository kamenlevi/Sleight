import SwiftUI

@main
struct SleightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = ConfigStore.shared

    @State private var updater = Updater.shared

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
            if case .available(let version) = updater.state {
                Divider()
                Button("Update to \(version)…") {
                    Task { await updater.installAvailable() }
                }
            }
            if case .staged(let version) = updater.state {
                Divider()
                Button("Install Update \(version)") {
                    updater.applyStagedUpdate()
                }
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

        // Launched straight from the unzipped download, macOS runs the app
        // from a read-only translocation mount where self-update can never
        // work and permission grants don't stick. Move to Applications and
        // relaunch from there before doing anything else.
        if Updater.repairInstallLocationIfNeeded() { return }

        let firstLaunch = !UserDefaults.standard.bool(forKey: "com.kamenlevi.sleight.launchedBefore")
        UserDefaults.standard.set(true, forKey: "com.kamenlevi.sleight.launchedBefore")

        SleightLog.log("launch: accessibility=\(Permissions.accessibilityGranted) inputMonitoring(reported)=\(Permissions.inputMonitoringReportedGranted) inputMonitoring(working)=\(Permissions.inputMonitoringWorking) multitouch=\(MultitouchBridge.isAvailable)")

        // Prompt the system dialogs ONLY on the very first launch. On later
        // launches we never re-prompt — even if an API momentarily claims a
        // permission is missing — so a working install is never nagged.
        if firstLaunch {
            if !Permissions.inputMonitoringWorking {
                Permissions.requestInputMonitoring()
            }
            if !Permissions.accessibilityGranted {
                Permissions.requestAccessibility()
            }
        }

        GestureCoordinator.shared.start(initialConfig: ConfigStore.shared.config)
        if Permissions.accessibilityGranted {
            EventSuppressor.shared.start()
        }
        Updater.shared.start()
        AutomationScheduler.shared.start()

        // Bring subsystems up as permissions become effective, without ever
        // prompting. Grants don't apply retroactively to already-started
        // devices, so the touch stream is (re)started here once usable.
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
                // If a fresh Input Monitoring grant appeared after we started
                // the stream without it, restart to pick it up (grants aren't
                // retroactive). Never prompt.
                if Permissions.inputMonitoringReportedGranted,
                   !TouchStream.shared.startedWithInputMonitoring {
                    TouchStream.shared.start()
                }
                if !Permissions.inputMonitoringWorking {
                    done = false
                }
                if done {
                    self?.permissionPoll?.invalidate()
                    self?.permissionPoll = nil
                }
            }
        }

        // Only surface the settings window unprompted on first launch or when
        // something genuinely isn't working yet. (`--settings` forces it —
        // handy from the command line.)
        if firstLaunch || CommandLine.arguments.contains("--settings")
            || !Permissions.inputMonitoringWorking || !Permissions.accessibilityGranted {
            SettingsWindow.show(tab: .general)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        TouchStream.shared.stop()
    }
}
