import Foundation
import Observation

/// What a continuous (dial / arc) gesture controls.
enum ContinuousControl: String, Codable, CaseIterable, Identifiable {
    case volume
    case displayBrightness
    case keyboardBrightness
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .volume: "Volume"
        case .displayBrightness: "Display Brightness"
        case .keyboardBrightness: "Keyboard Brightness"
        case .none: "Off"
        }
    }

    var symbol: String {
        switch self {
        case .volume: "speaker.wave.3.fill"
        case .displayBrightness: "sun.max.fill"
        case .keyboardBrightness: "keyboard.fill"
        case .none: "circle.slash"
        }
    }
}

/// What a discrete (tap / shortcut) gesture triggers.
enum DiscreteAction: String, Codable, CaseIterable, Identifiable {
    case none
    case playPause
    case nextTrack
    case previousTrack
    case muteToggle
    case keyboardBrightnessCycle
    case launchApp
    case shellCommand
    // The "More" catalogue.
    case cycleInputSource
    case micMuteToggle
    case lockScreen
    case sleepDisplays
    case sleepMac
    case startScreenSaver
    case missionControl
    case showDesktop
    case toggleDarkMode
    case screenshotArea
    case screenshotScreen
    case volumeUp
    case volumeDown
    case displayBrightnessUp
    case displayBrightnessDown
    case keyboardBrightnessUp
    case keyboardBrightnessDown
    case appExpose
    case spaceLeft
    case spaceRight
    case spotlight
    case browserBack
    case browserForward
    case nextTab
    case previousTab
    case newTab
    case reopenClosedTab
    case closeTabOrWindow
    case minimizeWindow
    case hideApp
    case fullScreenToggle
    case zoomIn
    case zoomOut
    case emptyTrash

    var id: String { rawValue }

    /// The everyday actions shown at the top of every action picker.
    static let primary: [DiscreteAction] = [
        .none, .playPause, .nextTrack, .previousTrack, .muteToggle,
        .keyboardBrightnessCycle, .launchApp, .shellCommand,
    ]

    /// Everything else, revealed by the picker's "More…" row (searchable).
    static let more: [DiscreteAction] = [
        .cycleInputSource, .micMuteToggle,
        .volumeUp, .volumeDown, .displayBrightnessUp, .displayBrightnessDown,
        .keyboardBrightnessUp, .keyboardBrightnessDown,
        .missionControl, .appExpose, .showDesktop, .spaceLeft, .spaceRight,
        .spotlight,
        .browserBack, .browserForward, .nextTab, .previousTab, .newTab,
        .reopenClosedTab, .closeTabOrWindow, .minimizeWindow, .hideApp,
        .fullScreenToggle, .zoomIn, .zoomOut,
        .screenshotArea, .screenshotScreen,
        .lockScreen, .sleepDisplays, .sleepMac, .startScreenSaver,
        .toggleDarkMode, .emptyTrash,
    ]

    var label: String {
        switch self {
        case .none: "Off"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .muteToggle: "Mute / Unmute"
        case .keyboardBrightnessCycle: "Cycle Keyboard Backlight (off · mid · max)"
        case .launchApp: "Launch App…"
        case .shellCommand: "Run Shell Command…"
        case .cycleInputSource: "Next Keyboard Language"
        case .micMuteToggle: "Mute / Unmute Microphone"
        case .lockScreen: "Lock Screen"
        case .sleepDisplays: "Sleep Displays"
        case .sleepMac: "Sleep Mac"
        case .startScreenSaver: "Start Screen Saver"
        case .missionControl: "Mission Control"
        case .showDesktop: "Show Desktop"
        case .toggleDarkMode: "Toggle Light / Dark Mode"
        case .screenshotArea: "Screenshot Area to Clipboard"
        case .screenshotScreen: "Screenshot Screen to Clipboard"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .displayBrightnessUp: "Display Brightness Up"
        case .displayBrightnessDown: "Display Brightness Down"
        case .keyboardBrightnessUp: "Keyboard Backlight Up"
        case .keyboardBrightnessDown: "Keyboard Backlight Down"
        case .appExpose: "App Exposé"
        case .spaceLeft: "Move a Space Left"
        case .spaceRight: "Move a Space Right"
        case .spotlight: "Spotlight Search"
        case .browserBack: "Back (⌘[)"
        case .browserForward: "Forward (⌘])"
        case .nextTab: "Next Tab"
        case .previousTab: "Previous Tab"
        case .newTab: "New Tab"
        case .reopenClosedTab: "Reopen Closed Tab"
        case .closeTabOrWindow: "Close Tab / Window (⌘W)"
        case .minimizeWindow: "Minimize Window"
        case .hideApp: "Hide Current App"
        case .fullScreenToggle: "Toggle Full Screen"
        case .zoomIn: "Zoom In (⌘+)"
        case .zoomOut: "Zoom Out (⌘−)"
        case .emptyTrash: "Empty Trash"
        }
    }

    /// Actions that can be aimed at one specific app instead of acting
    /// system-wide: the media trio (scripted straight to that player, no
    /// matter what else is playing) and the keystroke-backed actions (the
    /// key combo is delivered to that app's process, even in the background).
    var supportsAppTarget: Bool {
        switch self {
        case .playPause, .nextTrack, .previousTrack,
             .browserBack, .browserForward, .nextTab, .previousTab, .newTab,
             .reopenClosedTab, .closeTabOrWindow, .minimizeWindow, .hideApp,
             .fullScreenToggle, .zoomIn, .zoomOut:
            true
        default:
            false
        }
    }

    var symbol: String {
        switch self {
        case .none: "circle.slash"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.fill"
        case .previousTrack: "backward.fill"
        case .muteToggle: "speaker.slash.fill"
        case .keyboardBrightnessCycle: "light.max"
        case .launchApp: "app.badge.checkmark"
        case .shellCommand: "terminal.fill"
        case .cycleInputSource: "globe"
        case .micMuteToggle: "mic.slash.fill"
        case .lockScreen: "lock.fill"
        case .sleepDisplays: "display"
        case .sleepMac: "moon.zzz.fill"
        case .startScreenSaver: "sparkles.tv"
        case .missionControl: "rectangle.3.group"
        case .showDesktop: "desktopcomputer"
        case .toggleDarkMode: "circle.lefthalf.filled"
        case .screenshotArea: "camera.viewfinder"
        case .screenshotScreen: "camera.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .displayBrightnessUp: "sun.max.fill"
        case .displayBrightnessDown: "sun.min.fill"
        case .keyboardBrightnessUp: "light.max"
        case .keyboardBrightnessDown: "light.min"
        case .appExpose: "square.grid.2x2"
        case .spaceLeft: "arrow.left.square"
        case .spaceRight: "arrow.right.square"
        case .spotlight: "magnifyingglass"
        case .browserBack: "chevron.backward"
        case .browserForward: "chevron.forward"
        case .nextTab: "arrow.right.to.line"
        case .previousTab: "arrow.left.to.line"
        case .newTab: "plus.square"
        case .reopenClosedTab: "arrow.uturn.backward"
        case .closeTabOrWindow: "xmark.square"
        case .minimizeWindow: "arrow.down.right.square"
        case .hideApp: "eye.slash"
        case .fullScreenToggle: "arrow.up.left.and.arrow.down.right"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .emptyTrash: "trash"
        }
    }
}

/// A global keyboard shortcut bound to a Sleight action. Captured by the
/// event tap before any app sees it.
struct ShortcutBinding: Codable, Equatable, Identifiable {
    var id = UUID()
    var enabled = true
    /// -1 until the user records a combination.
    var keyCode: Int = -1
    /// Canonical Keystrokes modifier bits.
    var modifiers: Int = 0
    var action: DiscreteAction = .keyboardBrightnessCycle
    var appPath = ""
    var shellCommand = ""
    /// Optional .app path this action is aimed at.
    var targetApp: String?

    var isRecorded: Bool { keyCode >= 0 }
}

struct KeyboardLevel: Codable, Equatable, Identifiable {
    var id = UUID()
    var value: Double
    /// A disabled level stays in the list (greyed out) but the cycle skips it.
    var enabled = true
}

struct DialConfig: Codable, Equatable {
    var enabled = true
    var control: ContinuousControl = .volume
    /// 1.0 means one full rotation sweeps the whole 0–100% range.
    var sensitivity: Double = 1.0
    var inverted = false
}

/// The rails slider: one finger on the top edge, one on the bottom,
/// sweeping horizontally together. (A vertical variant existed briefly but
/// was removed — it competed directly with scrolling.)
struct SliderConfig: Codable, Equatable {
    var enabled = true
    var control: ContinuousControl = .keyboardBrightness
    /// 1.0 means sweeping ~70% of the pad covers the whole 0–100% range,
    /// so the physical distance scales with the trackpad's size.
    var sensitivity: Double = 1.0
    var inverted = false
}

// MARK: - Custom gestures

enum FingerDirection: String, Codable, CaseIterable, Identifiable {
    case none, up, down, left, right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Stationary"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        }
    }

    var symbol: String {
        switch self {
        case .none: "hand.raised.fill"
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }

    /// Unit vector in trackpad coordinates (origin bottom-left, y up).
    var vector: SIMD2<Float>? {
        switch self {
        case .none: nil
        case .up: SIMD2(0, 1)
        case .down: SIMD2(0, -1)
        case .left: SIMD2(-1, 0)
        case .right: SIMD2(1, 0)
        }
    }
}

enum SpeedRequirement: String, Codable, CaseIterable, Identifiable {
    case any, slow, fast

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: "Any speed"
        case .slow: "Slow, deliberate"
        case .fast: "Quick flick"
        }
    }
}

struct BoundaryPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct CustomFinger: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Landing zone center, normalized trackpad coordinates (y up).
    var x: Double
    var y: Double
    /// Landing zone radius.
    var radius: Double = 0.22
    var direction: FingerDirection = .none
}

struct CustomGesture: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "New Gesture"
    var enabled = true
    var fingers: [CustomFinger] = [
        CustomFinger(x: 0.35, y: 0.5, direction: .up),
        CustomFinger(x: 0.65, y: 0.5, direction: .up),
    ]
    /// true: motion adjusts a continuous control; false: fires an action once.
    var isContinuous = true
    var control: ContinuousControl = .volume
    var action: DiscreteAction = .playPause
    var appPath = ""
    var shellCommand = ""
    /// Optional .app path this action is aimed at.
    var targetApp: String?
    var sensitivity: Double = 1.0
    var speed: SpeedRequirement = .any
    /// Optional drawn outline: when present (3+ points), the gesture is only
    /// detected if every finger lands inside this polygon. Optional so
    /// configs saved before this field existed still decode.
    var boundary: [BoundaryPoint]?

    var summary: String {
        let what = isContinuous ? control.label : action.label
        return "\(fingers.count) finger\(fingers.count == 1 ? "" : "s") → \(what)"
    }
}

// MARK: - Automations

/// What a scheduled automation does when its time arrives.
enum AutomationAction: String, Codable, CaseIterable, Identifiable {
    case setVolume
    case setDisplayBrightness
    case setKeyboardBrightness
    case mute
    case unmute
    case playPause
    case nextTrack
    case previousTrack
    case keyboardBrightnessCycle
    case launchApp
    case shellCommand

    var id: String { rawValue }

    /// Actions that set something to a specific percentage.
    var usesLevel: Bool {
        switch self {
        case .setVolume, .setDisplayBrightness, .setKeyboardBrightness: true
        default: false
        }
    }

    /// Media actions can be aimed at one specific player.
    var supportsAppTarget: Bool {
        switch self {
        case .playPause, .nextTrack, .previousTrack: true
        default: false
        }
    }

    var label: String {
        switch self {
        case .setVolume: "Set Volume to…"
        case .setDisplayBrightness: "Set Display Brightness to…"
        case .setKeyboardBrightness: "Set Keyboard Backlight to…"
        case .mute: "Mute"
        case .unmute: "Unmute"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .keyboardBrightnessCycle: "Cycle Keyboard Backlight"
        case .launchApp: "Launch App…"
        case .shellCommand: "Run Shell Command…"
        }
    }

    var symbol: String {
        switch self {
        case .setVolume: "speaker.wave.2.fill"
        case .setDisplayBrightness: "sun.max.fill"
        case .setKeyboardBrightness: "keyboard.fill"
        case .mute: "speaker.slash.fill"
        case .unmute: "speaker.fill"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.fill"
        case .previousTrack: "backward.fill"
        case .keyboardBrightnessCycle: "light.max"
        case .launchApp: "app.badge.checkmark"
        case .shellCommand: "terminal.fill"
        }
    }
}

/// A job that runs at a set time on chosen days — e.g. keyboard backlight to
/// 20% at 21:00 every day, or volume to 0 at 9:00 on weekdays.
struct Automation: Codable, Equatable, Identifiable {
    var id = UUID()
    var enabled = true
    var action: AutomationAction = .setKeyboardBrightness
    /// 0…1 target for the set-to-percentage actions.
    var level: Double = 0.5
    var appPath = ""
    var shellCommand = ""
    /// Optional .app path the media actions are aimed at.
    var targetApp: String?
    var hour = 9
    var minute = 0
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday).
    var weekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]

    var summary: String {
        let time = String(format: "%02d:%02d", hour, minute)
        return "\(time) → \(action.label)"
    }
}

struct TapConfig: Codable, Equatable {
    var action: DiscreteAction = .none
    var appPath: String = ""
    var shellCommand: String = ""
    /// Optional .app path this action is aimed at (see DiscreteAction
    /// .supportsAppTarget). Optional so configs from before this field
    /// existed still decode.
    var targetApp: String?
}

struct SleightConfig: Codable, Equatable {
    var twoFingerDial = DialConfig(control: .volume)
    var threeFingerDial = DialConfig(control: .displayBrightness)
    var slider = SliderConfig(control: .keyboardBrightness)
    var threeFingerTap = TapConfig()
    var fourFingerTap = TapConfig()
    var fiveFingerTap = TapConfig()
    var customGestures: [CustomGesture] = []
    var shortcuts: [ShortcutBinding] = []
    var automations: [Automation] = []
    var hapticDetents = true
    var showHUD = true
    /// Flash a short HUD confirmation when a tap/shortcut fires an action
    /// with no visible effect of its own. Off by default — actions run
    /// silently unless the user opts in.
    var actionConfirmations = false
    /// Swallow scroll/swipe input the moment a gesture posture is detected,
    /// so pages can't move or navigate back/forward while a gesture forms.
    /// (This blocks input, not rendering — videos keep playing.)
    var freezeScreen = true
    /// Additionally pin the pointer in place while a gesture is active.
    var freezePointer = false
    /// Levels the keyboard-backlight cycle steps through, as actual hardware
    /// fractions (shown as real percentages in the HUD). User-editable; a
    /// level can be disabled (kept in the list but skipped by the cycle).
    var keyboardLevels: [KeyboardLevel] = [
        KeyboardLevel(value: 0), KeyboardLevel(value: 0.2), KeyboardLevel(value: 1.0),
    ]
    /// Multiplier on HUD animation durations: higher = faster (1.0 = default).
    var animationSpeed: Double = 1.0
    /// When a popup appears after the previous one already faded away, animate
    /// its bar travelling from the old value (e.g. 100 → 0). Off by default:
    /// a fresh popup appears already at its value.
    var animateHUDReappear = false
    var enabled = true

    enum CodingKeys: String, CodingKey {
        case twoFingerDial, threeFingerDial, slider
        case threeFingerTap, fourFingerTap, fiveFingerTap
        case customGestures, shortcuts, automations
        case hapticDetents, showHUD, actionConfirmations, freezeScreen, freezePointer
        case keyboardLevels, animationSpeed, animateHUDReappear, enabled
    }
}

// Tolerant decoding so settings survive config-shape changes across versions:
// unknown old keys are ignored, missing new keys get defaults.
extension SleightConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SleightConfig()
        twoFingerDial = (try? c.decodeIfPresent(DialConfig.self, forKey: .twoFingerDial)) ?? nil ?? defaults.twoFingerDial
        threeFingerDial = (try? c.decodeIfPresent(DialConfig.self, forKey: .threeFingerDial)) ?? nil ?? defaults.threeFingerDial
        slider = (try? c.decodeIfPresent(SliderConfig.self, forKey: .slider)) ?? nil ?? defaults.slider
        threeFingerTap = (try? c.decodeIfPresent(TapConfig.self, forKey: .threeFingerTap)) ?? nil ?? defaults.threeFingerTap
        fourFingerTap = (try? c.decodeIfPresent(TapConfig.self, forKey: .fourFingerTap)) ?? nil ?? defaults.fourFingerTap
        fiveFingerTap = (try? c.decodeIfPresent(TapConfig.self, forKey: .fiveFingerTap)) ?? nil ?? defaults.fiveFingerTap
        customGestures = (try? c.decodeIfPresent([CustomGesture].self, forKey: .customGestures)) ?? nil ?? defaults.customGestures
        shortcuts = (try? c.decodeIfPresent([ShortcutBinding].self, forKey: .shortcuts)) ?? nil ?? defaults.shortcuts
        automations = (try? c.decodeIfPresent([Automation].self, forKey: .automations)) ?? nil ?? defaults.automations
        hapticDetents = (try? c.decodeIfPresent(Bool.self, forKey: .hapticDetents)) ?? nil ?? defaults.hapticDetents
        showHUD = (try? c.decodeIfPresent(Bool.self, forKey: .showHUD)) ?? nil ?? defaults.showHUD
        actionConfirmations = (try? c.decodeIfPresent(Bool.self, forKey: .actionConfirmations)) ?? nil ?? defaults.actionConfirmations
        freezeScreen = (try? c.decodeIfPresent(Bool.self, forKey: .freezeScreen)) ?? nil ?? defaults.freezeScreen
        freezePointer = (try? c.decodeIfPresent(Bool.self, forKey: .freezePointer)) ?? nil ?? defaults.freezePointer
        // Accept the new [KeyboardLevel] shape, or migrate the old [Double].
        if let levels = try? c.decode([KeyboardLevel].self, forKey: .keyboardLevels) {
            keyboardLevels = levels
        } else if let raw = try? c.decode([Double].self, forKey: .keyboardLevels) {
            keyboardLevels = raw.map { KeyboardLevel(value: $0) }
        } else {
            keyboardLevels = defaults.keyboardLevels
        }
        animationSpeed = (try? c.decodeIfPresent(Double.self, forKey: .animationSpeed)) ?? nil ?? defaults.animationSpeed
        animateHUDReappear = (try? c.decodeIfPresent(Bool.self, forKey: .animateHUDReappear)) ?? nil ?? defaults.animateHUDReappear
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? nil ?? defaults.enabled
    }
}

/// Single source of truth for user settings, persisted as JSON in defaults.
@MainActor
@Observable
final class ConfigStore {
    static let shared = ConfigStore()
    private static let key = "com.kamenlevi.sleight.config"

    var config: SleightConfig {
        didSet {
            guard config != oldValue else { return }
            scheduleSave()
            GestureCoordinator.shared.configChanged(config)
        }
    }

    private var pendingSave: DispatchWorkItem?

    private init() {
        var loaded: SleightConfig
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(SleightConfig.self, from: data) {
            loaded = decoded
        } else {
            loaded = SleightConfig()
        }
        // Drop accidental duplicates (same combination, same action).
        var seen = Set<String>()
        loaded.shortcuts = loaded.shortcuts.filter { shortcut in
            guard shortcut.isRecorded else { return true }
            let key = "\(shortcut.keyCode)-\(shortcut.modifiers)-\(shortcut.action.rawValue)"
            return seen.insert(key).inserted
        }
        config = loaded
    }

    /// Slider drags mutate config dozens of times per second; encode and
    /// write to disk only once things settle.
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let data = try? JSONEncoder().encode(self.config) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
