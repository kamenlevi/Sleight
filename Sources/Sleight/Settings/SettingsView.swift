import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var state = SettingsState.shared

    var body: some View {
        TabView(selection: Binding(
            get: { state.selectedTab },
            set: { state.selectedTab = $0 }
        )) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            GestureSettingsView()
                .tabItem { Label("Gestures", systemImage: "hand.draw") }
                .tag(SettingsTab.gestures)
            CustomGesturesView()
                .tabItem { Label("Custom", systemImage: "wand.and.stars") }
                .tag(SettingsTab.custom)
            ShortcutsView()
                .tabItem { Label("Shortcuts", systemImage: "command") }
                .tag(SettingsTab.shortcuts)
            VisualizerView()
                .tabItem { Label("Visualizer", systemImage: "dot.circle.and.hand.point.up.left.fill") }
                .tag(SettingsTab.visualizer)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 640, height: 600)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @State private var store = ConfigStore.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityOK = Permissions.accessibilityGranted
    @State private var inputMonitoringOK = Permissions.inputMonitoringWorking
    @State private var suppressorRunning = EventSuppressor.shared.isRunning

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Enable Sleight", isOn: $store.config.enabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enable in
                        do {
                            if enable {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section {
                Toggle("Show HUD while adjusting", isOn: $store.config.showHUD)
                Toggle("Haptic detents on the trackpad", isOn: $store.config.hapticDetents)
            } header: {
                Text("Feedback")
            } footer: {
                Text("Detents make the dial click softly every few percent, like a physical knob.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Freeze scrolling during gestures", isOn: $store.config.freezeScreen)
                Toggle("Also freeze the pointer during gestures", isOn: $store.config.freezePointer)
            } header: {
                Text("During Gestures")
            } footer: {
                Text("Freezing blocks scroll and swipe input the instant a gesture starts forming, so pages can't move or navigate back and forward underneath your fingers. Nothing is paused — videos keep playing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                PermissionRow(
                    title: "Input Monitoring",
                    detail: "Required to read raw finger positions from the trackpad.",
                    granted: inputMonitoringOK,
                    request: {
                        Permissions.requestInputMonitoring()
                        Permissions.openInputMonitoringSettings()
                    }
                )
                PermissionRow(
                    title: "Accessibility",
                    detail: "Stops the system from scrolling while you turn a dial, and enables media-key actions.",
                    granted: accessibilityOK,
                    request: {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                )
                if !accessibilityOK || !inputMonitoringOK {
                    HStack {
                        Text("Granted it but still shows ✕? The old entry is stale — Repair deletes it so you can grant once, cleanly.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Repair Permissions") {
                            Permissions.repair()
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Sleight only ever asks for these once. If a checkbox looks right in System Settings but Sleight still shows ✕, use Repair.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                KeyboardLevelsEditor(levels: $store.config.keyboardLevels)
            } header: {
                Text("Keyboard Backlight Cycle")
            } footer: {
                Text("The “Cycle Keyboard Backlight” action (a shortcut, tap, or custom gesture) steps through these levels in order, then wraps around. Percentages are the actual hardware brightness. Backlight LEDs aren’t perceptually even, so a low value like 20% often looks like a natural middle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Install updates automatically when the Mac wakes", isOn: $store.config.autoUpdate)
                LabeledContent("Version") {
                    Text(Updater.currentVersion)
                }
                UpdateStatusRow()
            } header: {
                Text("Updates")
            }

            Section("Trackpad") {
                LabeledContent("Multitouch devices detected") {
                    Text("\(TouchStream.shared.deviceCount)")
                        .foregroundStyle(TouchStream.shared.deviceCount > 0 ? .primary : Color.red)
                }
                LabeledContent("Freeze engine") {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(suppressorRunning ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(suppressorRunning ? "Active" : "Inactive — grant Accessibility")
                            .foregroundStyle(suppressorRunning ? .primary : Color.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(refresh) { _ in
            accessibilityOK = Permissions.accessibilityGranted
            inputMonitoringOK = Permissions.inputMonitoringWorking
            launchAtLogin = SMAppService.mainApp.status == .enabled
            suppressorRunning = EventSuppressor.shared.isRunning
        }
    }
}

private struct KeyboardLevelsEditor: View {
    @Binding var levels: [Double]

    private var sorted: [Double] {
        Array(Set(levels.map { min(max($0, 0), 1) })).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(sorted.enumerated()), id: \.offset) { index, level in
                HStack {
                    Image(systemName: iconFor(level))
                        .foregroundStyle(.tint)
                        .frame(width: 22)
                    Slider(
                        value: Binding(
                            get: { level },
                            set: { updateLevel(at: index, to: $0) }
                        ),
                        in: 0...1
                    )
                    Text(level, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                    Button {
                        KeyboardBacklight.shared.set(Float(level))
                    } label: {
                        Image(systemName: "eye")
                    }
                    .buttonStyle(.borderless)
                    .help("Preview this level")
                    Button(role: .destructive) {
                        removeLevel(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(sorted.count <= 2)
                }
            }
            Button {
                addLevel()
            } label: {
                Label("Add Level", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
    }

    private func iconFor(_ level: Double) -> String {
        if level <= 0.001 { return "light.min" }
        if level >= 0.999 { return "light.max" }
        return "keyboard.badge.ellipsis"
    }

    private func updateLevel(at index: Int, to value: Double) {
        var current = sorted
        guard index < current.count else { return }
        current[index] = min(max(value, 0), 1)
        levels = current
    }

    private func removeLevel(at index: Int) {
        var current = sorted
        guard index < current.count, current.count > 2 else { return }
        current.remove(at: index)
        levels = current
    }

    private func addLevel() {
        var current = sorted
        // Insert into the largest gap so the new level is useful by default.
        var bestGap = -1.0
        var newValue = 0.5
        let padded = [0.0] + current + [1.0]
        for i in 0..<(padded.count - 1) {
            let gap = padded[i + 1] - padded[i]
            if gap > bestGap {
                bestGap = gap
                newValue = (padded[i] + padded[i + 1]) / 2
            }
        }
        current.append((newValue * 100).rounded() / 100)
        levels = Array(Set(current)).sorted()
    }
}

private struct UpdateStatusRow: View {
    @State private var updater = Updater.shared

    var body: some View {
        HStack {
            switch updater.state {
            case .idle:
                Text("Updates are checked twice a day.")
                    .foregroundStyle(.secondary)
            case .checking:
                Text("Checking…").foregroundStyle(.secondary)
            case .upToDate:
                Text("You're on the latest version.")
                    .foregroundStyle(.secondary)
            case .downloading(let version):
                Text("Downloading \(version)…").foregroundStyle(.secondary)
            case .staged(let version):
                Text("\(version) ready — installing…")
                    .foregroundStyle(.green)
            case .failed(let message):
                Text("Check failed: \(message)")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer()
            Button("Check Now") {
                Task { await updater.check(userInitiated: true) }
            }
            .disabled(updater.state == .checking)
        }
        .font(.callout)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(granted ? .green : .orange)
                    Text(title)
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant…", action: request)
            }
        }
    }
}

// MARK: - Gestures

struct GestureSettingsView: View {
    @State private var store = ConfigStore.shared

    var body: some View {
        Form {
            Section {
                DialSection(
                    title: "Two-Finger Dial",
                    subtitle: "Place two fingers (thumb and index work great) and rotate them like a knob.",
                    symbol: "dial.medium.fill",
                    config: $store.config.twoFingerDial
                )
            }
            Section {
                DialSection(
                    title: "Three-Finger Dial",
                    subtitle: "Same knob motion with three fingers — e.g. index and middle together, thumb below.",
                    symbol: "dial.high.fill",
                    config: $store.config.threeFingerDial
                )
            }
            Section {
                SliderSection(config: $store.config.slider)
            }

            if store.config.customGestures.contains(where: { $0.enabled }) {
                Section {
                    ForEach(store.config.customGestures.filter(\.enabled)) { gesture in
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gesture.name).fontWeight(.medium)
                                    Text(gesture.summary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: gesture.isContinuous
                                      ? gesture.control.symbol
                                      : gesture.action.symbol)
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .frame(width: 30)
                            }
                            Spacer()
                            Button("Edit") {
                                SettingsState.shared.selectedTab = .custom
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Your Custom Gestures")
                }
            }

            Section {
                TapRow(title: "Three-finger tap", config: $store.config.threeFingerTap)
                TapRow(title: "Four-finger tap", config: $store.config.fourFingerTap)
                TapRow(title: "Five-finger tap", config: $store.config.fiveFingerTap)
            } header: {
                Text("Taps")
            } footer: {
                Text("If a tap seems to trigger twice, check for overlapping gestures in System Settings → Trackpad.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DialSection: View {
    let title: String
    let subtitle: String
    let symbol: String
    @Binding var config: DialConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).fontWeight(.medium)
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 30)
                }
                Spacer()
                Toggle("", isOn: $config.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if config.enabled {
                Picker("Controls", selection: $config.control) {
                    ForEach(ContinuousControl.allCases) { control in
                        Label(control.label, systemImage: control.symbol).tag(control)
                    }
                }

                HStack {
                    Text("Sensitivity")
                    Slider(value: $config.sensitivity, in: 0.25...3.0)
                    Text(config.sensitivity, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                }

                Toggle("Reverse direction", isOn: $config.inverted)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SliderSection: View {
    @Binding var config: SliderConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edge Slider").fontWeight(.medium)
                        Text("Rest one finger on the top edge and one on the bottom (same spot horizontally), then sweep both left or right together.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 30)
                }
                Spacer()
                Toggle("", isOn: $config.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if config.enabled {
                Picker("Controls", selection: $config.control) {
                    ForEach(ContinuousControl.allCases) { control in
                        Label(control.label, systemImage: control.symbol).tag(control)
                    }
                }

                HStack {
                    Text("Sensitivity")
                    Slider(value: $config.sensitivity, in: 0.25...3.0)
                    Text(config.sensitivity, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                }

                Toggle("Reverse direction", isOn: $config.inverted)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TapRow: View {
    let title: String
    @Binding var config: TapConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(title, selection: $config.action) {
                ForEach(DiscreteAction.allCases) { action in
                    Label(action.label, systemImage: action.symbol).tag(action)
                }
            }

            if config.action == .launchApp {
                HStack {
                    Text(config.appPath.isEmpty
                         ? "No app selected"
                         : (config.appPath as NSString).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                    Button("Choose App…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.application]
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        if panel.runModal() == .OK, let url = panel.url {
                            config.appPath = url.path
                        }
                    }
                }
            }

            if config.action == .shellCommand {
                TextField("Command", text: $config.shellCommand, prompt: Text("say hello"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
            }
        }
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dial.medium.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Sleight")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Turn your Magic Trackpad into a control surface.")
                .foregroundStyle(.secondary)
            Text("Version \(Updater.currentVersion)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Link("github.com/kamenlevi/Sleight",
                 destination: URL(string: "https://github.com/kamenlevi/Sleight")!)
                .font(.callout)
            Text("Free and open source · MIT License")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
