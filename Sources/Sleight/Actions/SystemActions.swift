import AppKit
import Carbon
import CoreAudio

/// One-shot system actions available from the "More" section of the action
/// pickers. Each is fire-and-forget; the ones with no visible effect of
/// their own report back a string for the HUD flash.
enum SystemActions {

    // MARK: - Keyboard input source

    /// Switches to the next enabled keyboard layout / input method and
    /// returns its localized name, or nil when there's nothing to cycle to.
    static func cycleInputSource() -> String? {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue()
                as? [TISInputSource], list.count > 1 else { return nil }
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let currentID = property(current, kTISPropertyInputSourceID)
        let index = list.firstIndex { property($0, kTISPropertyInputSourceID) == currentID } ?? 0
        let next = list[(index + 1) % list.count]
        guard TISSelectInputSource(next) == noErr else { return nil }
        return property(next, kTISPropertyLocalizedName)
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    // MARK: - Microphone

    /// Toggles mute on the default input device. Returns the new muted
    /// state, or nil when the device exposes no mute control.
    static func toggleMicMute() -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &muteAddress) else { return nil }
        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &muteSize, &muted) == noErr
        else { return nil }
        var newValue: UInt32 = muted == 0 ? 1 : 0
        guard AudioObjectSetPropertyData(device, &muteAddress, 0, nil, muteSize, &newValue) == noErr
        else { return nil }
        return newValue == 1
    }

    // MARK: - Screen & session

    static func sleepDisplays() { run("/usr/bin/pmset", ["displaysleepnow"]) }
    static func sleepMac() { run("/usr/bin/pmset", ["sleepnow"]) }

    static func startScreenSaver() {
        run("/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine", [])
    }

    // Direct exec of the Mission Control binary gets SIGKILLed on current
    // macOS — it must be launched through LaunchServices.
    static func missionControl() {
        run("/usr/bin/open", ["-b", "com.apple.exposelauncher"])
    }

    private static func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags = [], pid: pid_t? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        if let pid {
            down?.postToPid(pid)
            up?.postToPid(pid)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Flips the system appearance. First use asks the user to allow Sleight
    /// to control System Events (a one-time macOS automation prompt).
    static func toggleDarkMode() {
        run("/usr/bin/osascript", ["-e",
            "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"])
    }

    /// Interactive area screenshot straight to the clipboard (⌃⇧⌘4-style).
    /// macOS may ask for Screen Recording on first use.
    static func screenshotArea() {
        run("/usr/sbin/screencapture", ["-i", "-c"])
    }

    /// The whole screen to the clipboard, no interaction.
    static func screenshotScreen() {
        run("/usr/sbin/screencapture", ["-c"])
    }

    /// Asks Finder to empty the trash (one-time automation consent).
    static func emptyTrash() {
        run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"])
    }

    // MARK: - App-targeted actions

    /// Resolve a configured .app path to its running process, if any.
    private static func runningApp(at path: String) -> NSRunningApplication? {
        guard let bundleID = Bundle(path: path)?.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Media command aimed at one specific player, no matter what else is
    /// playing: scripted directly to that app (first use asks the one-time
    /// automation consent for it). Command variants cover the different
    /// dialects — Music/Spotify say "playpause", VLC says "play". If the
    /// target isn't running, nothing happens — deliberately: controlling
    /// some *other* player instead would be exactly the bug this avoids.
    static func mediaCommand(_ variants: [String], appPath: String) {
        guard let bundleID = Bundle(path: appPath)?.bundleIdentifier else {
            SleightLog.log("target media: no bundle at \(appPath)")
            return
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            SleightLog.log("target media: \(bundleID) not running — doing nothing")
            return
        }
        let attempts = variants.map { "try\n\($0)\nreturn\nend try" }.joined(separator: "\n")
        let script = "tell application id \"\(bundleID)\"\n\(attempts)\nend tell"
        run("/usr/bin/osascript", ["-e", script])
    }

    static let playPauseVariants = ["playpause", "play"]
    static let nextTrackVariants = ["next track", "next"]
    static let previousTrackVariants = ["previous track", "previous"]

    // MARK: - Keystroke actions

    /// Actions that are, honestly, just the system's own keyboard shortcut —
    /// synthesized the same way as lockScreen. With no target they act on
    /// whatever app is frontmost, exactly like pressing the keys yourself;
    /// with a target the combo is posted straight to that app's process
    /// (which works for most apps even in the background). A set target
    /// that isn't running means the action does nothing.
    static func keystroke(for action: DiscreteAction, toAppAt targetPath: String? = nil) -> Bool {
        let map: [DiscreteAction: (CGKeyCode, CGEventFlags)] = [
            .appExpose: (125, .maskControl),          // ⌃↓
            .spaceLeft: (123, .maskControl),          // ⌃←
            .spaceRight: (124, .maskControl),         // ⌃→
            .showDesktop: (103, []),                  // F11
            .spotlight: (49, .maskCommand),           // ⌘Space
            .browserBack: (33, .maskCommand),         // ⌘[
            .browserForward: (30, .maskCommand),      // ⌘]
            .nextTab: (48, .maskControl),             // ⌃Tab
            .previousTab: (48, [.maskControl, .maskShift]),
            .newTab: (17, .maskCommand),              // ⌘T
            .reopenClosedTab: (17, [.maskCommand, .maskShift]),
            .closeTabOrWindow: (13, .maskCommand),    // ⌘W
            .minimizeWindow: (46, .maskCommand),      // ⌘M
            .hideApp: (4, .maskCommand),              // ⌘H
            .fullScreenToggle: (3, [.maskControl, .maskCommand]), // ⌃⌘F
            .zoomIn: (24, .maskCommand),              // ⌘=
            .zoomOut: (27, .maskCommand),             // ⌘-
            .lockScreen: (12, [.maskControl, .maskCommand]),      // ⌃⌘Q
        ]
        guard let (key, flags) = map[action] else { return false }
        if let targetPath, !targetPath.isEmpty {
            guard let app = runningApp(at: targetPath) else {
                SleightLog.log("target keystroke: app at \(targetPath) not running — doing nothing")
                return true
            }
            pressKey(key, flags: flags, pid: app.processIdentifier)
        } else {
            pressKey(key, flags: flags)
        }
        return true
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            SleightLog.log("action: could not run \(path): \(error.localizedDescription)")
        }
    }
}
