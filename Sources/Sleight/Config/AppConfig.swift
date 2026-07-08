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

    var id: String { rawValue }

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

    var isRecorded: Bool { keyCode >= 0 }
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

struct TapConfig: Codable, Equatable {
    var action: DiscreteAction = .none
    var appPath: String = ""
    var shellCommand: String = ""
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
    var hapticDetents = true
    var showHUD = true
    /// Swallow scroll/swipe input the moment a gesture posture is detected,
    /// so pages can't move or navigate back/forward while a gesture forms.
    /// (This blocks input, not rendering — videos keep playing.)
    var freezeScreen = true
    /// Additionally pin the pointer in place while a gesture is active.
    var freezePointer = false
    /// Install downloaded updates automatically when the Mac wakes.
    var autoUpdate = true
    var enabled = true

    enum CodingKeys: String, CodingKey {
        case twoFingerDial, threeFingerDial, slider
        case threeFingerTap, fourFingerTap, fiveFingerTap
        case customGestures, shortcuts
        case hapticDetents, showHUD, freezeScreen, freezePointer, autoUpdate, enabled
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
        hapticDetents = (try? c.decodeIfPresent(Bool.self, forKey: .hapticDetents)) ?? nil ?? defaults.hapticDetents
        showHUD = (try? c.decodeIfPresent(Bool.self, forKey: .showHUD)) ?? nil ?? defaults.showHUD
        freezeScreen = (try? c.decodeIfPresent(Bool.self, forKey: .freezeScreen)) ?? nil ?? defaults.freezeScreen
        freezePointer = (try? c.decodeIfPresent(Bool.self, forKey: .freezePointer)) ?? nil ?? defaults.freezePointer
        autoUpdate = (try? c.decodeIfPresent(Bool.self, forKey: .autoUpdate)) ?? nil ?? defaults.autoUpdate
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
