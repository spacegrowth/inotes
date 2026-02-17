import SwiftUI

struct ContentView: View {
    @ObservedObject var store: NotesStore

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(selectedIndex: $store.selectedIndex, notes: $store.notes)
            Divider()
            NoteEditorView(
                content: Binding(
                    get: { store.notes[store.selectedIndex].content },
                    set: { store.updateContent(at: store.selectedIndex, content: $0) }
                )
            )
        }
        .background(.background)
    }
}
