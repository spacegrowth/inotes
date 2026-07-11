import SwiftUI

struct ContentView: View {
    @ObservedObject var store: NotesStore
    @StateObject private var editorState = EditorState()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabBarView(store: store)
                Button {
                    store.showToolbar.toggle()
                } label: {
                    Image(systemName: "textformat")
                        .font(.system(size: 11))
                        .frame(width: 24, height: 24)
                        .foregroundColor(store.showToolbar ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .help("Toggle formatting toolbar")
            }
            Divider()
            if store.showToolbar {
                FormattingToolbar(editorState: editorState)
                Divider()
            }
            NoteEditorView(
                text: textBinding(at: store.selectedIndex),
                noteID: store.notes[store.selectedIndex].id,
                editorState: editorState
            )
            Divider()
            StatusFooterView(
                text: store.notes[store.selectedIndex].text,
                lastModified: store.notes[store.selectedIndex].lastModified
            )
            .id(store.notes[store.selectedIndex].id)
        }
        .background(.background)
    }

    /// Binding pinned to a specific note index. Capturing `index` (rather than
    /// reading `store.selectedIndex` live) keeps the binding pointed at the same
    /// note even after the selection changes, so the editor's debounced save
    /// still writes the outgoing note's edits to the outgoing note.
    private func textBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { store.notes[index].text },
            set: { store.updateText(at: index, text: $0) }
        )
    }
}
