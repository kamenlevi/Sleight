import SwiftUI

/// Build-your-own gestures: place finger zones on a trackpad canvas, give
/// each a direction (or keep it stationary), pick what the gesture controls.
struct CustomGesturesView: View {
    @State private var store = ConfigStore.shared
    @State private var selectedGestureID: UUID?
    @State private var selectedFingerID: UUID?

    private var selectedIndex: Int? {
        store.config.customGestures.firstIndex { $0.id == selectedGestureID }
    }

    var body: some View {
        HSplitView {
            gestureList
                .frame(minWidth: 180, maxWidth: 220)
            if let index = selectedIndex {
                GestureEditor(
                    gesture: $store.config.customGestures[index],
                    selectedFingerID: $selectedFingerID,
                    onDelete: {
                        let id = store.config.customGestures[index].id
                        store.config.customGestures.removeAll { $0.id == id }
                        selectedGestureID = store.config.customGestures.first?.id
                    }
                )
            } else {
                emptyState
            }
        }
        .onAppear {
            selectedGestureID = store.config.customGestures.first?.id
        }
    }

    private var gestureList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedGestureID) {
                ForEach(store.config.customGestures) { gesture in
                    HStack {
                        Image(systemName: gesture.isContinuous
                              ? gesture.control.symbol
                              : gesture.action.symbol)
                            .foregroundStyle(gesture.enabled ? Color.accentColor : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(gesture.name)
                                .fontWeight(.medium)
                            Text("\(gesture.fingers.count) finger\(gesture.fingers.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(gesture.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Button {
                    var gesture = CustomGesture()
                    gesture.name = "Gesture \(store.config.customGestures.count + 1)"
                    store.config.customGestures.append(gesture)
                    selectedGestureID = gesture.id
                    selectedFingerID = gesture.fingers.first?.id
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .padding(6)
                Spacer()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.draw")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Design your own gesture")
                .font(.headline)
            Text("Click + to create one. Place finger zones on the pad, give each a direction, and choose what it controls.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Editor

private struct GestureEditor: View {
    @Binding var gesture: CustomGesture
    @Binding var selectedFingerID: UUID?
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField("Name", text: $gesture.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                    Toggle("", isOn: $gesture.enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Text("Drag the circles to where each finger should land. Select one to set its movement.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                FingerCanvas(fingers: $gesture.fingers, selectedFingerID: $selectedFingerID)
                    .aspectRatio(1.6, contentMode: .fit)

                HStack {
                    Button {
                        var finger = CustomFinger(x: 0.5, y: 0.3)
                        finger.direction = .none
                        gesture.fingers.append(finger)
                        selectedFingerID = finger.id
                    } label: {
                        Label("Add Finger", systemImage: "plus.circle")
                    }
                    .disabled(gesture.fingers.count >= 5)

                    if let fingerIndex = gesture.fingers.firstIndex(where: { $0.id == selectedFingerID }) {
                        Picker("Moves", selection: $gesture.fingers[fingerIndex].direction) {
                            ForEach(FingerDirection.allCases) { direction in
                                Label(direction.label, systemImage: direction.symbol).tag(direction)
                            }
                        }
                        .frame(maxWidth: 200)

                        Button(role: .destructive) {
                            let id = gesture.fingers[fingerIndex].id
                            gesture.fingers.removeAll { $0.id == id }
                            selectedFingerID = gesture.fingers.first?.id
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .disabled(gesture.fingers.count <= 1)
                    }
                    Spacer()
                }

                Divider()

                Picker("When performed", selection: $gesture.isContinuous) {
                    Text("Adjust a control").tag(true)
                    Text("Trigger an action").tag(false)
                }
                .pickerStyle(.segmented)

                if gesture.isContinuous {
                    Picker("Controls", selection: $gesture.control) {
                        ForEach(ContinuousControl.allCases.filter { $0 != .none }) { control in
                            Label(control.label, systemImage: control.symbol).tag(control)
                        }
                    }
                    HStack {
                        Text("Sensitivity")
                        Slider(value: $gesture.sensitivity, in: 0.25...3.0)
                        Text(gesture.sensitivity, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                    }
                } else {
                    Picker("Action", selection: $gesture.action) {
                        ForEach(DiscreteAction.allCases.filter { $0 != .none }) { action in
                            Label(action.label, systemImage: action.symbol).tag(action)
                        }
                    }
                    if gesture.action == .launchApp {
                        HStack {
                            Text(gesture.appPath.isEmpty
                                 ? "No app selected"
                                 : (gesture.appPath as NSString).lastPathComponent)
                                .foregroundStyle(.secondary)
                                .font(.callout)
                            Spacer()
                            Button("Choose App…") {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.application]
                                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                                if panel.runModal() == .OK, let url = panel.url {
                                    gesture.appPath = url.path
                                }
                            }
                        }
                    }
                    if gesture.action == .shellCommand {
                        TextField("Command", text: $gesture.shellCommand, prompt: Text("say hello"))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.callout, design: .monospaced))
                    }
                }

                Picker("Speed", selection: $gesture.speed) {
                    ForEach(SpeedRequirement.allCases) { speed in
                        Text(speed.label).tag(speed)
                    }
                }

                if !gesture.fingers.contains(where: { $0.direction != .none }), gesture.isContinuous {
                    Label("An adjusting gesture needs at least one finger with a direction.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Gesture", systemImage: "trash")
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Canvas

private struct FingerCanvas: View {
    @Binding var fingers: [CustomFinger]
    @Binding var selectedFingerID: UUID?

    private let fingerColors: [Color] = [.blue, .green, .orange, .pink, .purple]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.tertiary, lineWidth: 1)

                ForEach(Array(fingers.enumerated()), id: \.element.id) { index, finger in
                    let center = CGPoint(
                        x: finger.x * geo.size.width,
                        // Config uses trackpad coordinates (y up); flip for the view.
                        y: (1 - finger.y) * geo.size.height
                    )
                    let zoneRadius = finger.radius * geo.size.width / 1.6
                    let color = fingerColors[index % fingerColors.count]
                    let isSelected = finger.id == selectedFingerID

                    ZStack {
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(color.opacity(0.5))
                            .frame(width: zoneRadius * 2, height: zoneRadius * 2)
                        Circle()
                            .fill(color.gradient)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle().strokeBorder(
                                    isSelected ? Color.primary : .white.opacity(0.5),
                                    lineWidth: isSelected ? 2.5 : 1.5
                                )
                            )
                        Image(systemName: finger.direction.symbol)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .position(center)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                selectedFingerID = finger.id
                                guard let i = fingers.firstIndex(where: { $0.id == finger.id }) else { return }
                                fingers[i].x = min(max(drag.location.x / geo.size.width, 0.02), 0.98)
                                fingers[i].y = min(max(1 - drag.location.y / geo.size.height, 0.02), 0.98)
                            }
                    )
                }
            }
        }
    }
}
