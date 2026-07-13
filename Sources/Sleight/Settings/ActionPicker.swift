import AppKit
import SwiftUI

/// Shown under the action picker for actions that can be aimed at one
/// specific app (see DiscreteAction.supportsAppTarget): media commands go
/// straight to that player no matter what else is playing; keystroke
/// actions are delivered to that app even while it's in the background.
/// If the chosen app isn't running, the action deliberately does nothing.
struct TargetAppRow: View {
    @Binding var targetApp: String?

    private var appName: String? {
        targetApp.flatMap { $0.isEmpty ? nil : $0 }
            .map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .foregroundStyle(.secondary)
                .font(.callout)
            Text(appName.map { "Only \($0)" } ?? "Whatever app is active")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button(appName == nil ? "Only in App…" : "Change…") { choose() }
            if appName != nil {
                Button {
                    targetApp = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Back to system-wide")
            }
        }
        .help("Aim this action at one specific app — e.g. play/pause only your music player, no matter what else is playing. Does nothing when that app isn't running.")
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            targetApp = url.path
        }
    }
}

/// The shared action picker used by taps, shortcuts and custom gestures.
/// Looks like a popup button; opens a panel with the everyday actions on
/// top and a collapsed "More…" row. Clicking More reveals a search field
/// (below the baseline actions, above the catalogue) and the full list.
struct DiscreteActionPicker: View {
    let title: String
    @Binding var action: DiscreteAction
    /// Taps offer "Off"; shortcut and custom-gesture rows don't (delete the
    /// row instead).
    var includeOff = true

    @State private var open = false

    var body: some View {
        HStack {
            if !title.isEmpty {
                Text(title)
                Spacer()
            }
            Button {
                open.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: action.symbol)
                        .foregroundStyle(.tint)
                        .frame(width: 16)
                    Text(action.label)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ActionCatalog(selection: $action, includeOff: includeOff, open: $open)
            }
        }
    }

}

struct ActionCatalog: View {
    @Binding var selection: DiscreteAction
    let includeOff: Bool
    @Binding var open: Bool

    @State private var showMore: Bool
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    init(selection: Binding<DiscreteAction>, includeOff: Bool, open: Binding<Bool>) {
        _selection = selection
        self.includeOff = includeOff
        _open = open
        // If the current action lives in the catalogue, open straight to it.
        _showMore = State(initialValue: DiscreteAction.more.contains(selection.wrappedValue))
    }

    private var baseline: [DiscreteAction] {
        DiscreteAction.primary.filter { includeOff || $0 != .none }
    }

    private var filtered: [DiscreteAction] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return DiscreteAction.more }
        return DiscreteAction.more.filter { $0.label.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(baseline) { action in
                row(action)
            }

            Divider().padding(.vertical, 4)

            if showMore {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    TextField("Search actions", text: $search)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
                .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(filtered) { action in
                            row(action)
                        }
                        if filtered.isEmpty {
                            Text("Nothing matches “\(search)”")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                    }
                }
                .frame(height: 240)
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.15)) { showMore = true }
                    searchFocused = true
                } label: {
                    HStack {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 18)
                        Text("More…")
                        Spacer()
                        Text("\(DiscreteAction.more.count) actions")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(HoverRowStyle())
            }
        }
        .padding(10)
        .frame(width: 300)
    }

    private func row(_ action: DiscreteAction) -> some View {
        Button {
            selection = action
            open = false
        } label: {
            HStack {
                Image(systemName: action.symbol)
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                Text(action.label)
                    .lineLimit(1)
                Spacer()
                if action == selection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
    }
}

/// Menu-item-like rows: full-width, highlight on hover.
private struct HoverRowStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering || configuration.isPressed
                          ? Color.accentColor.opacity(configuration.isPressed ? 0.25 : 0.15)
                          : Color.clear)
            )
            .onHover { hovering = $0 }
    }
}
