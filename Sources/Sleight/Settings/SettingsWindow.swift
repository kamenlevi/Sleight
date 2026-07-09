import AppKit
import SwiftUI

/// Manual window management keeps the settings window reliable in a
/// menu-bar-only (LSUIElement) app.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(tab: SettingsTab? = nil) {
        if let tab {
            SettingsState.shared.selectedTab = tab
        }
        if let window {
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Sleight"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        // Follow the user: opening the window from another desktop moves it
        // there instead of yanking them back to where it was first opened.
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.setContentSize(NSSize(width: 640, height: 600))
        window.center()
        Self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

enum SettingsTab: String {
    case general
    case gestures
    case custom
    case shortcuts
    case automation
    case visualizer
    case about
}

@MainActor
@Observable
final class SettingsState {
    static let shared = SettingsState()
    var selectedTab: SettingsTab = .gestures
}
