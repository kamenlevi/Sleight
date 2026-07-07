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

/// What a discrete (tap) gesture triggers.
enum DiscreteAction: String, Codable, CaseIterable, Identifiable {
    case none
    case playPause
    case nextTrack
    case previousTrack
    case muteToggle
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
        case .launchApp: "app.badge.checkmark"
        case .shellCommand: "terminal.fill"
        }
    }
}

struct DialConfig: Codable, Equatable {
    var enabled = true
    var control: ContinuousControl = .volume
    /// 1.0 means one full rotation sweeps the whole 0–100% range.
    var sensitivity: Double = 1.0
    var inverted = false
}

enum SliderMode: String, Codable, CaseIterable, Identifiable {
    /// Two fingers side by side, starting at the very top or bottom edge,
    /// swiping vertically.
    case verticalFromEdge
    /// One finger on the top edge, one on the bottom, sweeping horizontally
    /// together.
    case horizontalRails

    var id: String { rawValue }

    var label: String {
        switch self {
        case .verticalFromEdge: "Swipe up/down from an edge"
        case .horizontalRails: "Top + bottom fingers, sweep sideways"
        }
    }

    var help: String {
        switch self {
        case .verticalFromEdge:
            "Start with two fingers at the very top or bottom edge of the pad, then swipe vertically — the pad becomes a slider."
        case .horizontalRails:
            "Rest one finger on the top edge and one on the bottom (same spot horizontally), then sweep both left or right together."
        }
    }
}

struct SliderConfig: Codable, Equatable {
    var enabled = true
    var control: ContinuousControl = .keyboardBrightness
    /// 1.0 means sweeping ~70% of the pad covers the whole 0–100% range,
    /// so the physical distance scales with the trackpad's size.
    var sensitivity: Double = 1.0
    var inverted = false
    var mode: SliderMode = .verticalFromEdge
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
    var hapticDetents = true
    var showHUD = true
    var enabled = true

    enum CodingKeys: String, CodingKey {
        case twoFingerDial, threeFingerDial, slider
        case threeFingerTap, fourFingerTap, fiveFingerTap
        case hapticDetents, showHUD, enabled
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
        hapticDetents = (try? c.decodeIfPresent(Bool.self, forKey: .hapticDetents)) ?? nil ?? defaults.hapticDetents
        showHUD = (try? c.decodeIfPresent(Bool.self, forKey: .showHUD)) ?? nil ?? defaults.showHUD
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
            save()
            GestureCoordinator.shared.configChanged(config)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(SleightConfig.self, from: data) {
            config = decoded
        } else {
            config = SleightConfig()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
