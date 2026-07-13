import SwiftUI

/// The shared action dropdown used by taps, shortcuts and custom gestures:
/// the everyday actions on top, and the whole extended catalogue in a
/// "More" group at the bottom.
struct DiscreteActionPicker: View {
    let title: String
    @Binding var action: DiscreteAction
    /// Taps offer "Off"; shortcut and custom-gesture rows don't (delete the
    /// row instead).
    var includeOff = true

    var body: some View {
        Picker(title, selection: $action) {
            ForEach(DiscreteAction.primary.filter { includeOff || $0 != .none }) { action in
                Label(action.label, systemImage: action.symbol).tag(action)
            }
            Section("More") {
                ForEach(DiscreteAction.more) { action in
                    Label(action.label, systemImage: action.symbol).tag(action)
                }
            }
        }
    }
}
