import SwiftUI
import UniformTypeIdentifiers

struct TabBarView: View {
    @ObservedObject var store: NotesStore
    @State private var editingID: UUID? = nil
    @State private var draggingID: UUID? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(store.notes) { note in
                TabItemView(
                    title: titleBinding(for: note.id),
                    isSelected: isSelected(note),
                    isPinned: note.isPinned,
                    isEditing: Binding(
                        get: { editingID == note.id },
                        set: { editing in editingID = editing ? note.id : nil }
                    ),
                    canDelete: store.notes.count > 1,
                    onSelect: { select(note) },
                    onDelete: { store.deleteNote(id: note.id) },
                    onTogglePin: { togglePin(note) }
                )
                .opacity(draggingID == note.id ? 0.4 : 1.0)
                .onDrag {
                    draggingID = note.id
                    return NSItemProvider(object: note.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: TabDropDelegate(
                    item: note,
                    notes: store.notes,
                    draggingID: $draggingID,
                    move: { from, to in store.moveNote(from: from, to: to) }
                ))
            }
            Button(action: { store.addNote() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .disabled(!store.canAddNote)
            .opacity(store.canAddNote ? 1.0 : 0.3)
            .help(store.canAddNote ? "New note" : "Maximum \(NotesStore.maxNotes) notes")
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func isSelected(_ note: Note) -> Bool {
        store.notes.indices.contains(store.selectedIndex) && store.notes[store.selectedIndex].id == note.id
    }

    private func select(_ note: Note) {
        if let index = store.notes.firstIndex(where: { $0.id == note.id }) {
            store.selectedIndex = index
        }
    }

    private func togglePin(_ note: Note) {
        if let index = store.notes.firstIndex(where: { $0.id == note.id }) {
            store.togglePin(at: index)
        }
    }

    private func titleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { store.notes.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let index = store.notes.firstIndex(where: { $0.id == id }) {
                    store.notes[index].title = newValue
                }
            }
        )
    }
}

/// Live-reorder drop delegate: as the dragged tab hovers over another tab,
/// swap their positions immediately (standard macOS/iOS drag-reorder feel).
private struct TabDropDelegate: DropDelegate {
    let item: Note
    let notes: [Note]
    @Binding var draggingID: UUID?
    let move: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != item.id,
              let from = notes.firstIndex(where: { $0.id == draggingID }),
              let to = notes.firstIndex(where: { $0.id == item.id }) else { return }
        move(from, to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

struct TabItemView: View {
    @Binding var title: String
    let isSelected: Bool
    let isPinned: Bool
    @Binding var isEditing: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 3) {
            if isPinned {
                Text("📌")
                    .font(.system(size: 8))
            }
            if isEditing {
                TextField("", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onSubmit { isEditing = false }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { isEditing = false }
                    }
                    .onAppear { isFocused = true }
            } else {
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            if isHovering && !isEditing && canDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Delete note")
            }
        }
        .foregroundColor(isSelected ? Color(nsColor: NSColor(white: 0.25, alpha: 1.0)) : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in isHovering = hovering }
        .onTapGesture(count: 2) {
            onSelect()
            isEditing = true
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .contextMenu {
            Button(isPinned ? "Unpin" : "Pin", action: onTogglePin)
            Divider()
            Button("Delete", action: onDelete)
                .disabled(!canDelete)
        }
    }
}
