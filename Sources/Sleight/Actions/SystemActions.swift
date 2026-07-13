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

    /// Real Lock Screen (the ⌃⌘Q one), via a synthetic keystroke — the only
    /// non-private way in. Needs Accessibility, which Sleight already uses.
    static func lockScreen() {
        pressKey(12, flags: [.maskCommand, .maskControl]) // ⌃⌘Q
    }

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

    /// Show Desktop = a synthetic F11, the default macOS binding (the
    /// exposelauncher argument trick no longer verifiably works).
    static func showDesktop() {
        pressKey(103) // F11
    }

    private static func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
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
