import SwiftUI
import UniformTypeIdentifiers

/// A grab handle — three stacked lines — shown at the leading edge of a
/// reorderable row. Grab it and drag up or down; the other rows slide out of
/// the way as you go, the way you'd drag a song around a playlist.
struct DragHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body)
            .foregroundStyle(.tertiary)
            .frame(width: 22, height: 28)
            .contentShape(Rectangle())
            .help("Drag to reorder")
    }
}

/// Live reordering for rows laid out by hand (inside a Form, where List's
/// `.onMove` isn't available). As the dragged row passes over another, the
/// array is reordered on the spot so everything animates into place. Pair it
/// with `DragHandle().onDrag { … }` on the same rows.
struct ReorderDropDelegate<Item: Identifiable>: DropDelegate {
    let item: Item
    @Binding var items: [Item]
    @Binding var dragging: Item.ID?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item.id,
              let from = items.firstIndex(where: { $0.id == dragging }),
              let to = items.firstIndex(where: { $0.id == item.id })
        else { return }
        withAnimation {
            items.move(fromOffsets: IndexSet(integer: from),
                       toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

extension View {
    /// Marks this view as a reorderable row: `handleID` starts the drag (put
    /// it on the DragHandle), and dropping anywhere on the row moves the
    /// dragged item to this row's slot in `items`.
    func reorderable<Item: Identifiable>(
        _ item: Item,
        in items: Binding<[Item]>,
        dragging: Binding<Item.ID?>
    ) -> some View where Item.ID == UUID {
        onDrop(
            of: [.text],
            delegate: ReorderDropDelegate(item: item, items: items, dragging: dragging)
        )
    }
}
