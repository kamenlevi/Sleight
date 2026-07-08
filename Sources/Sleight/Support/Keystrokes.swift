import AppKit
import CoreGraphics

/// Canonical modifier bits, key names, and the "what you'd be giving up"
/// database for keyboard shortcuts.
enum Keystrokes {
    static let cmd = 1
    static let opt = 2
    static let ctrl = 4
    static let shift = 8
    static let fn = 16

    /// Keys that report the fn/function flag on their own (arrows, F-keys,
    /// paging keys) — holding fn is not meaningful for them, so it is
    /// stripped to keep recording and matching consistent.
    static let functionalKeys: Set<Int> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1–F12
        123, 124, 125, 126,                                     // arrows
        115, 116, 119, 121, 117, 114,                           // home/pgup/end/pgdn/fwd-del/help
    ]

    static func canonical(_ flags: NSEvent.ModifierFlags, keyCode: Int) -> Int {
        var bits = 0
        if flags.contains(.command) { bits |= cmd }
        if flags.contains(.option) { bits |= opt }
        if flags.contains(.control) { bits |= ctrl }
        if flags.contains(.shift) { bits |= shift }
        if flags.contains(.function), !functionalKeys.contains(keyCode) { bits |= fn }
        return bits
    }

    static func canonical(_ flags: CGEventFlags, keyCode: Int) -> Int {
        var bits = 0
        if flags.contains(.maskCommand) { bits |= cmd }
        if flags.contains(.maskAlternate) { bits |= opt }
        if flags.contains(.maskControl) { bits |= ctrl }
        if flags.contains(.maskShift) { bits |= shift }
        if flags.contains(.maskSecondaryFn), !functionalKeys.contains(keyCode) { bits |= fn }
        return bits
    }

    private static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        32: "U", 31: "O", 35: "P", 34: "I", 37: "L", 38: "J", 40: "K", 45: "N",
        46: "M", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9", 29: "0", 27: "-", 24: "=", 33: "[", 30: "]", 41: ";",
        39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 116: "Page Up", 119: "End", 121: "Page Down", 117: "⌦",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func name(for keyCode: Int) -> String {
        keyNames[keyCode] ?? "key \(keyCode)"
    }

    static func display(keyCode: Int, modifiers: Int) -> String {
        var parts: [String] = []
        if modifiers & fn != 0 { parts.append("🌐") }
        if modifiers & ctrl != 0 { parts.append("⌃") }
        if modifiers & opt != 0 { parts.append("⌥") }
        if modifiers & shift != 0 { parts.append("⇧") }
        if modifiers & cmd != 0 { parts.append("⌘") }
        parts.append(name(for: keyCode))
        return parts.joined()
    }

    /// What macOS (or convention) already uses a combination for — shown so
    /// the user knows what they are giving up by rebinding it.
    static func systemConflict(keyCode: Int, modifiers: Int) -> String? {
        struct Known {
            let keyCode: Int
            let modifiers: Int
            let does: String
        }
        let known: [Known] = [
            Known(keyCode: 49, modifiers: cmd, does: "Spotlight"),
            Known(keyCode: 49, modifiers: opt, does: "typing a non-breaking space in text fields (rarely used)"),
            Known(keyCode: 49, modifiers: cmd | opt, does: "Finder search window"),
            Known(keyCode: 49, modifiers: ctrl, does: "switching input sources"),
            Known(keyCode: 49, modifiers: ctrl | cmd, does: "the Emoji & Symbols picker"),
            Known(keyCode: 49, modifiers: fn, does: "Page Down in some apps"),
            Known(keyCode: 48, modifiers: cmd, does: "the app switcher"),
            Known(keyCode: 50, modifiers: cmd, does: "cycling app windows"),
            Known(keyCode: 20, modifiers: cmd | shift, does: "full-screen screenshots"),
            Known(keyCode: 21, modifiers: cmd | shift, does: "area screenshots"),
            Known(keyCode: 23, modifiers: cmd | shift, does: "the screenshot toolbar"),
            Known(keyCode: 53, modifiers: cmd | opt, does: "Force Quit"),
            Known(keyCode: 12, modifiers: cmd, does: "quitting the current app"),
            Known(keyCode: 13, modifiers: cmd, does: "closing the current window"),
            Known(keyCode: 4, modifiers: cmd, does: "hiding the current app"),
            Known(keyCode: 46, modifiers: cmd, does: "minimizing the window"),
            Known(keyCode: 12, modifiers: ctrl | cmd, does: "locking the screen"),
            Known(keyCode: 3, modifiers: ctrl | cmd, does: "toggling full screen"),
            Known(keyCode: 123, modifiers: ctrl, does: "switching to the left Space"),
            Known(keyCode: 124, modifiers: ctrl, does: "switching to the right Space"),
            Known(keyCode: 126, modifiers: ctrl, does: "Mission Control"),
            Known(keyCode: 125, modifiers: ctrl, does: "App Exposé"),
            Known(keyCode: 14, modifiers: fn, does: "the emoji picker (Globe-E)"),
            Known(keyCode: 3, modifiers: fn, does: "full screen (Globe-F)"),
            Known(keyCode: 4, modifiers: fn, does: "showing the desktop (Globe-H)"),
            Known(keyCode: 12, modifiers: fn, does: "Quick Note (Globe-Q)"),
            Known(keyCode: 8, modifiers: fn, does: "Control Center (Globe-C)"),
            Known(keyCode: 45, modifiers: fn, does: "Notification Center (Globe-N)"),
            Known(keyCode: 2, modifiers: fn, does: "Dictation (Globe-D)"),
            Known(keyCode: 46, modifiers: fn, does: "focusing the menu bar (Globe-M)"),
            Known(keyCode: 103, modifiers: 0, does: "showing the desktop (F11)"),
        ]
        if let match = known.first(where: { $0.keyCode == keyCode && $0.modifiers == modifiers }) {
            return "This combination normally triggers \(match.does) — Sleight will take it over, so that stops working while Sleight runs."
        }
        if modifiers & fn != 0 {
            return "Globe (fn) combinations can be reserved by macOS (System Settings → Keyboard). If nothing happens when you press it, macOS is consuming it first — pick a different combination."
        }
        return nil
    }
}
