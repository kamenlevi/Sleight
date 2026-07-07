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

struct TapConfig: Codable, Equatable {
    var action: DiscreteAction = .none
    var appPath: String = ""
    var shellCommand: String = ""
}

struct SleightConfig: Codable, Equatable {
    var twoFingerDial = DialConfig(control: .volume)
    var threeFingerDial = DialConfig(control: .displayBrightness)
    var holdArc = DialConfig(control: .keyboardBrightness)
    var threeFingerTap = TapConfig()
    var fourFingerTap = TapConfig()
    var fiveFingerTap = TapConfig()
    var hapticDetents = true
    var showHUD = true
    var enabled = true
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
