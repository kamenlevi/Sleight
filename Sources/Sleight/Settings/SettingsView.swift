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
    @State private var inputMonitoringOK = Permissions.inputMonitoringGranted
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

            Section("Permissions") {
                PermissionRow(
                    title: "Input Monitoring",
                    detail: "Required to read raw finger positions from the trackpad. If it shows enabled in System Settings but still reads ✕ here, toggle Sleight off and on in that list.",
                    granted: inputMonitoringOK,
                    request: {
                        Permissions.requestInputMonitoring()
                        Permissions.openInputMonitoringSettings()
                    }
                )
                PermissionRow(
                    title: "Accessibility",
                    detail: "Stops the system from scrolling while you turn a dial, and enables media-key actions. If it shows enabled in System Settings but still reads ✕ here, toggle Sleight off and on in that list — after an update the old entry no longer counts.",
                    granted: accessibilityOK,
                    request: {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                )
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
            inputMonitoringOK = Permissions.inputMonitoringGranted
            launchAtLogin = SMAppService.mainApp.status == .enabled
            suppressorRunning = EventSuppressor.shared.isRunning
        }
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
            Text("Version 1.0")
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
