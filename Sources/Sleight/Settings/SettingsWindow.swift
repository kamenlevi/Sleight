import AppKit
import SwiftUI

/// Manual window management keeps the settings window reliable in a
/// menu-bar-only (LSUIElement) app.
///
/// While the window is open, Sleight temporarily becomes a *regular* app —
/// dock icon, ⌘-tab entry, real menu bar — so switching away and back works
/// like any other application instead of the window feeling like a one-shot
/// dialog. Closing the window returns Sleight to its menu-bar-only life.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static let windowDelegate = Delegate()

    static func show(tab: SettingsTab? = nil) {
        if let tab {
            SettingsState.shared.selectedTab = tab
        }
        becomeRegularApp()
        if let window {
            window.collectionBehavior.insert(.moveToActiveSpace)
            bringToFront(window)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Sleight"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate
        // Follow the user: opening the window from another desktop moves it
        // there instead of yanking them back to where it was first opened.
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.setContentSize(NSSize(width: 640, height: 600))
        window.center()
        Self.window = window
        bringToFront(window)
    }

    /// Raising the window has to fight two things when the click came from the
    /// menu bar: Sleight usually isn't the active app, so a plain
    /// `makeKeyAndOrderFront` leaves an already-open window sitting behind
    /// whatever is frontmost; and the status-item menu is still tearing down,
    /// which can swallow the activation entirely. So: un-minimize, order front
    /// regardless of who is active, and activate again on the next runloop
    /// pass once the menu is gone.
    private static func bringToFront(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func becomeRegularApp() {
        installMainMenu()
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
    }

    private final class Delegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            // Back to a pure menu-bar app: no dock icon, no ⌘-tab entry.
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// A real main menu for the regular-app mode. Besides looking right, the
    /// Edit menu is what makes ⌘C/⌘V/⌘A work in the settings text fields,
    /// and File gives the window a standard ⌘W.
    private static var menuInstalled = false
    private static func installMainMenu() {
        guard !menuInstalled else { return }
        menuInstalled = true

        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Sleight",
                        action: #selector(AppMenuTarget.showAbout), keyEquivalent: "")
            .target = appMenuTarget
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Sleight",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Sleight",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    private static let appMenuTarget = AppMenuTarget()
    private final class AppMenuTarget: NSObject {
        @objc func showAbout() {
            // Menu actions arrive on the main thread.
            MainActor.assumeIsolated { SettingsWindow.show(tab: .about) }
        }
    }
}

enum SettingsTab: String, Codable, CaseIterable, Identifiable {
    case general
    case gestures
    case custom
    case shortcuts
    case automation
    case visualizer
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .gestures: "Gestures"
        case .custom: "Custom"
        case .shortcuts: "Shortcuts"
        case .automation: "Automation"
        case .visualizer: "Visualizer"
        case .about: "About"
        }
    }

    /// Left-to-right order of the tab bar out of the box; users can drag the
    /// tabs into whatever order they prefer (stored in `tabOrder`).
    static let defaultOrder: [SettingsTab] = [
        .general, .shortcuts, .automation, .gestures, .custom, .visualizer, .about,
    ]

    /// A stored order can be stale: written by an older version that didn't
    /// have every tab, or by a newer one that had more. Keep what's still
    /// valid, drop duplicates, and append anything missing in default order,
    /// so the bar always shows every tab exactly once.
    static func sanitizedOrder(_ stored: [SettingsTab]) -> [SettingsTab] {
        var seen = Set<SettingsTab>()
        var order = stored.filter { seen.insert($0).inserted }
        order.append(contentsOf: defaultOrder.filter { !seen.contains($0) })
        return order
    }
}

@MainActor
@Observable
final class SettingsState {
    static let shared = SettingsState()
    var selectedTab: SettingsTab = .gestures
}
