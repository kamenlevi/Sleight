import SwiftUI

/// Global keyboard shortcuts bound to Sleight actions, with honest warnings
/// about what each combination normally does in macOS.
struct ShortcutsView: View {
    @State private var store = ConfigStore.shared

    var body: some View {
        Form {
            Section {
                if store.config.shortcuts.isEmpty {
                    Text("No shortcuts yet. Add one and press the keys you want — for example 🌐Space to cycle the keyboard backlight.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                ForEach(store.config.shortcuts) { shortcut in
                    ShortcutRow(binding: binding(for: shortcut.id)) {
                        store.config.shortcuts.removeAll { $0.id == shortcut.id }
                    }
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Sleight captures these combinations before any other app sees them, system-wide. If a combination already does something in macOS, that function stops working while Sleight runs — the warning under each shortcut tells you exactly what you're giving up.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    store.config.shortcuts.append(ShortcutBinding())
                } label: {
                    Label("Add Shortcut", systemImage: "plus.circle")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Row bindings resolved by ID on every access, so rows keep working
    /// (and deleting) correctly no matter how the array shifts underneath.
    private func binding(for id: UUID) -> Binding<ShortcutBinding> {
        Binding(
            get: {
                ConfigStore.shared.config.shortcuts.first { $0.id == id } ?? ShortcutBinding()
            },
            set: { newValue in
                if let index = ConfigStore.shared.config.shortcuts.firstIndex(where: { $0.id == id }) {
                    ConfigStore.shared.config.shortcuts[index] = newValue
                }
            }
        )
    }
}

private struct ShortcutRow: View {
    @Binding var binding: ShortcutBinding
    let onDelete: () -> Void

    private var conflict: String? {
        guard binding.isRecorded else { return nil }
        return Keystrokes.systemConflict(keyCode: binding.keyCode, modifiers: binding.modifiers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $binding.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                ShortcutRecorder(keyCode: $binding.keyCode, modifiers: $binding.modifiers)

                Picker("", selection: $binding.action) {
                    ForEach(DiscreteAction.allCases.filter { $0 != .none }) { action in
                        Label(action.label, systemImage: action.symbol).tag(action)
                    }
                }
                .labelsHidden()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            if binding.action == .launchApp {
                HStack {
                    Text(binding.appPath.isEmpty
                         ? "No app selected"
                         : (binding.appPath as NSString).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                    Button("Choose App…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.application]
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        if panel.runModal() == .OK, let url = panel.url {
                            binding.appPath = url.path
                        }
                    }
                }
            }
            if binding.action == .shellCommand {
                TextField("Command", text: $binding.shellCommand, prompt: Text("say hello"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
            }

            if let conflict {
                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Click, then press the combination. Esc cancels.
private struct ShortcutRecorder: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stopRecording() : startRecording()
        } label: {
            Text(recording
                 ? "Press keys…"
                 : (keyCode >= 0 ? Keystrokes.display(keyCode: keyCode, modifiers: modifiers) : "Record Shortcut"))
                .font(.system(.body, design: .rounded).weight(.medium))
                .frame(minWidth: 130)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        // Prefer the session event tap: it sees virtually every combination,
        // including ones macOS would otherwise claim before a per-app monitor
        // could see them (⌘Space, ⌘Tab, screenshot keys, …). Fall back to a
        // local monitor when the tap isn't running (Accessibility not granted).
        if EventSuppressor.shared.canCaptureRecording {
            EventSuppressor.shared.beginRecordingCapture { code, mods in
                Task { @MainActor in accept(code: code, mods: mods) }
            }
        } else {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                accept(code: Int(event.keyCode),
                       mods: Keystrokes.canonical(event.modifierFlags, keyCode: Int(event.keyCode)))
                return nil
            }
        }
    }

    private func accept(code: Int, mods: Int) {
        if code == 53, mods == 0 { // Esc cancels
            stopRecording()
            return
        }
        // Require at least one modifier for ordinary keys (a bare letter would
        // shadow typing); functional keys (F-keys, arrows, paging, media) are
        // fine on their own. Everything else is accepted.
        if mods == 0, !Keystrokes.functionalKeys.contains(code) {
            NSSound.beep()
            return
        }
        keyCode = code
        modifiers = mods
        stopRecording()
    }

    private func stopRecording() {
        recording = false
        EventSuppressor.shared.endRecordingCapture()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
