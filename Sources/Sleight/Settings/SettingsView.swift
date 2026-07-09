import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var state = SettingsState.shared

    private struct TabItem: Identifiable {
        let tab: SettingsTab
        let title: String
        var id: SettingsTab { tab }
    }

    private let tabs: [TabItem] = [
        .init(tab: .general, title: "General"),
        .init(tab: .gestures, title: "Gestures"),
        .init(tab: .custom, title: "Custom"),
        .init(tab: .shortcuts, title: "Shortcuts"),
        .init(tab: .visualizer, title: "Visualizer"),
        .init(tab: .about, title: "About"),
    ]

    // A small, text-only custom tab bar instead of SwiftUI's TabView: on
    // macOS 26 the native tab strip paints a Liquid Glass blob behind the
    // selected item that looks different depending on the viewer's
    // Transparency setting. This renders identically everywhere.
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(tabs) { item in
                    TabBarButton(
                        title: item.title,
                        isSelected: state.selectedTab == item.tab
                    ) {
                        state.selectedTab = item.tab
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.background)

            Divider()

            Group {
                switch state.selectedTab {
                case .general: GeneralSettingsView()
                case .gestures: GestureSettingsView()
                case .custom: CustomGesturesView()
                case .shortcuts: ShortcutsView()
                case .visualizer: VisualizerView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 600)
    }
}

private struct TabBarButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                // Constant weight in all states: switching selection must not
                // change any label's width, or the whole bar reflows slightly.
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected
                              ? Color.accentColor.opacity(0.12)
                              : (hovering ? Color.primary.opacity(0.06) : Color.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
                HStack {
                    Text("Animation speed")
                    Slider(value: $store.config.animationSpeed, in: 0.5...2.5)
                    Text(store.config.animationSpeed, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    Text("×")
                        .foregroundStyle(.secondary)
                }
                Toggle("Animate the bar on a reappearing popup", isOn: $store.config.animateHUDReappear)
            } header: {
                Text("Feedback")
            } footer: {
                Text("Detents make the dial click softly every few percent, like a physical knob. Animation speed scales how quickly the HUD fades and its bar moves — higher is snappier. When the last option is off, a popup that reappears after fading shows its value immediately instead of sliding from the old one (e.g. 100 → 0).")
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
                        Text("Just granted it? Relaunch so it takes effect. Still ✕ after that, Repair clears a stale entry.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Relaunch") {
                            Permissions.relaunch()
                        }
                        Button("Repair") {
                            Permissions.repair()
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Sleight only ever asks for these once. Because macOS caches Accessibility per running process, a just-granted permission usually needs a relaunch to register.")
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
    @Binding var levels: [KeyboardLevel]

    /// Row order follows value, but each row keeps its stable id so edits and
    /// the enable animation stay attached to the right level.
    private var ordered: [KeyboardLevel] {
        levels.sorted { $0.value < $1.value }
    }

    private var enabledCount: Int { levels.filter(\.enabled).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ordered) { level in
                LevelRow(
                    level: bindingFor(level.id),
                    canDisable: level.enabled ? enabledCount > 2 : true,
                    canRemove: levels.count > 2,
                    onRemove: { levels.removeAll { $0.id == level.id } }
                )
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

    private func bindingFor(_ id: UUID) -> Binding<KeyboardLevel> {
        Binding(
            get: { levels.first { $0.id == id } ?? KeyboardLevel(value: 0) },
            set: { newValue in
                if let i = levels.firstIndex(where: { $0.id == id }) {
                    levels[i] = newValue
                }
            }
        )
    }

    private func addLevel() {
        // Insert into the largest gap so the new level is useful by default.
        let values = levels.map(\.value).sorted()
        var bestGap = -1.0
        var newValue = 0.5
        let padded = [0.0] + values + [1.0]
        for i in 0..<(padded.count - 1) {
            let gap = padded[i + 1] - padded[i]
            if gap > bestGap {
                bestGap = gap
                newValue = (padded[i] + padded[i + 1]) / 2
            }
        }
        levels.append(KeyboardLevel(value: (newValue * 100).rounded() / 100))
    }
}

private struct LevelRow: View {
    @Binding var level: KeyboardLevel
    let canDisable: Bool
    let canRemove: Bool
    let onRemove: () -> Void

    private var icon: String {
        if level.value <= 0.001 { return "light.min" }
        if level.value >= 0.999 { return "light.max" }
        return "keyboard.badge.ellipsis"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(level.enabled ? .primary : .secondary)
                .frame(width: 20)

            Slider(
                value: Binding(
                    get: { level.value },
                    set: { level.value = min(max($0, 0), 1) }
                ),
                in: 0...1
            ) { editing in
                // Live preview while dragging.
                if editing { KeyboardBacklight.shared.set(Float(level.value)) }
            }
            .disabled(!level.enabled)

            Text(level.value, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)

            // Eye toggle: open = active in the cycle, closed lid = kept but
            // skipped. Clicking blinks it shut / open.
            Button {
                if level.enabled, !canDisable { NSSound.beep(); return }
                withAnimation(.snappy(duration: 0.22)) {
                    level.enabled.toggle()
                }
                if level.enabled {
                    KeyboardBacklight.shared.set(Float(level.value))
                }
            } label: {
                EyeToggleIcon(open: level.enabled)
                    .frame(width: 24, height: 18)
            }
            .buttonStyle(.borderless)
            .help(level.enabled ? "Active — click to skip this level" : "Skipped — click to include it")

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(!canRemove)
        }
        .opacity(level.enabled ? 1 : 0.55)
    }
}

/// An eye that blinks: open shows the iris, closed shows a lidded curve with
/// little lashes — clearer than a slash for "this level is hidden".
private struct EyeToggleIcon: View {
    let open: Bool

    var body: some View {
        ZStack {
            Image(systemName: "eye")
                .foregroundStyle(Color.accentColor)
                .opacity(open ? 1 : 0)
                .scaleEffect(open ? 1 : 0.85)
            ClosedEye()
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                .opacity(open ? 0 : 1)
        }
        .font(.system(size: 15))
    }
}

private struct ClosedEye: Shape {
    private func quad(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(x: mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x,
                       y: mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y)
    }

    func path(in r: CGRect) -> Path {
        var path = Path()
        // A downturned lid: the ends sit high and the curve dips to its
        // lowest point in the middle (an upside-down rainbow).
        let p0 = CGPoint(x: r.minX + r.width * 0.08, y: r.minY + r.height * 0.32)
        let p1 = CGPoint(x: r.maxX - r.width * 0.08, y: r.minY + r.height * 0.32)
        let c = CGPoint(x: r.midX, y: r.minY + r.height * 0.95)
        path.move(to: p0)
        path.addQuadCurve(to: p1, control: c)
        // Three lashes hang from the outside of the curve, fanning out/down.
        let lashes: [(t: CGFloat, dx: CGFloat)] =
            [(0.2, -0.5), (0.5, 0), (0.8, 0.5)]
        for lash in lashes {
            let base = quad(p0, c, p1, lash.t)
            path.move(to: base)
            path.addLine(to: CGPoint(
                x: base.x + lash.dx * r.width * 0.14,
                y: base.y + r.height * 0.34
            ))
        }
        return path
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
