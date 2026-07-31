import SwiftUI

/// Scheduled jobs: at a chosen time on chosen days, perform any Sleight
/// action — set a level, mute, media keys, launch an app, run a command.
struct AutomationView: View {
    @State private var store = ConfigStore.shared
    @State private var dragging: UUID?

    var body: some View {
        Form {
            if store.config.automations.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No automations yet", systemImage: "clock.badge.checkmark")
                            .fontWeight(.medium)
                        Text("An automation performs an action at a set time on the days you pick — like dimming the keyboard backlight to 20% at 21:00, or muting every weekday morning at 9:00.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            ForEach(store.config.automations) { automation in
                Section {
                    AutomationRow(
                        automation: bindingFor(automation.id),
                        dragging: $dragging,
                        onRemove: {
                            store.config.automations.removeAll { $0.id == automation.id }
                        }
                    )
                    .reorderable(automation, in: $store.config.automations, dragging: $dragging)
                }
            }

            Section {
                Button {
                    store.config.automations.append(Automation())
                } label: {
                    Label("Add Automation", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            } footer: {
                Text("Automations run while Sleight is running. A time that passes while the Mac is asleep — or while Sleight is closed — runs as soon as it comes back, unless it's more than 6 hours late.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            WakeHelperSection()
        }
        .formStyle(.grouped)
    }

    /// By-ID binding: rows keep working after deletions reorder the array.
    private func bindingFor(_ id: UUID) -> Binding<Automation> {
        Binding(
            get: { store.config.automations.first { $0.id == id } ?? Automation() },
            set: { newValue in
                if let i = store.config.automations.firstIndex(where: { $0.id == id }) {
                    store.config.automations[i] = newValue
                }
            }
        )
    }
}

/// Opt-in to the privileged wake helper. Off by default and clearly explained:
/// it asks for an admin password and leaves a root daemon behind, which is not
/// something to switch on for someone.
private struct WakeHelperSection: View {
    @State private var helper = WakeHelper.shared
    @State private var store = ConfigStore.shared

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { helper.isInstalled },
                set: { wanted in wanted ? helper.install() : helper.uninstall() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake the Mac to run automations")
                    Text(helper.isInstalled
                         ? "Installed. The Mac wakes briefly for each automation, runs it at the scheduled time, and goes back to sleep."
                         : "Without this, an automation due while the Mac is asleep runs at the next wake instead — usually within about 15 minutes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(helper.busy)

            if let error = helper.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("While Asleep")
        } footer: {
            Text("Setting the backlight or the volume is something a running program does, so the Mac has to be awake for it. Only macOS can schedule a wake, and only with administrator rights — so this installs a small background helper, which asks for your password once. It does nothing but book those wake-ups, and turning this off removes it again. Waking costs a little battery each time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            helper.refresh()
            if helper.isInstalled { helper.writeSchedule(store.config) }
        }
    }
}

private struct AutomationRow: View {
    @Binding var automation: Automation
    @Binding var dragging: UUID?
    let onRemove: () -> Void

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(hour: automation.hour, minute: automation.minute)
                ) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                automation.hour = parts.hour ?? 9
                automation.minute = parts.minute ?? 0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DragHandle()
                    .onDrag {
                        dragging = automation.id
                        return NSItemProvider(object: automation.id.uuidString as NSString)
                    }
                Image(systemName: automation.action.symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                Toggle("", isOn: $automation.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }

            Group {
                Picker("Action", selection: $automation.action) {
                    ForEach(AutomationAction.allCases) { action in
                        Label(action.label, systemImage: action.symbol).tag(action)
                    }
                }

                if automation.action.usesLevel {
                    HStack {
                        Text("Level")
                        Slider(value: $automation.level, in: 0...1)
                        Text(automation.level, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                if automation.action == .launchApp {
                    HStack {
                        Text(automation.appPath.isEmpty
                             ? "No app selected"
                             : (automation.appPath as NSString).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                        Button("Choose App…") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.application]
                            panel.directoryURL = URL(fileURLWithPath: "/Applications")
                            if panel.runModal() == .OK, let url = panel.url {
                                automation.appPath = url.path
                            }
                        }
                    }
                }

                if automation.action == .shellCommand {
                    TextField("Command", text: $automation.shellCommand, prompt: Text("say hello"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                }

                if automation.action.supportsAppTarget {
                    TargetAppRow(targetApp: $automation.targetApp)
                }

                WeekdayPicker(selection: $automation.weekdays)
            }
            .disabled(!automation.enabled)
            .opacity(automation.enabled ? 1 : 0.55)
        }
        .padding(.vertical, 4)
    }
}

/// Seven round day toggles, Monday first. At least one day stays selected —
/// a job that can never run is only ever confusing.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    /// (Calendar weekday number, label)
    private let days: [(Int, String)] = [
        (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            Text("Days")
            Spacer()
            ForEach(days, id: \.0) { day, label in
                let isOn = selection.contains(day)
                Button {
                    if isOn {
                        guard selection.count > 1 else { NSSound.beep(); return }
                        selection.remove(day)
                    } else {
                        selection.insert(day)
                    }
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.08)))
                        .foregroundStyle(isOn ? Color.white : .secondary)
                }
                .buttonStyle(.plain)
                .help(fullName(day))
            }
        }
    }

    private func fullName(_ weekday: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names[weekday]
    }
}
