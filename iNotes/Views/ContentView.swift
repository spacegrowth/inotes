import SwiftUI

struct ContentView: View {
    @ObservedObject var store: NotesStore
    @StateObject private var editorState = EditorState()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabBarView(selectedIndex: $store.selectedIndex, notes: $store.notes)
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
                rtfData: Binding(
                    get: { store.notes[store.selectedIndex].rtfData },
                    set: { store.updateRTFData(at: store.selectedIndex, data: $0) }
                ),
                noteID: store.notes[store.selectedIndex].id,
                editorState: editorState
            )
        }
        .background(.background)
    }
}
