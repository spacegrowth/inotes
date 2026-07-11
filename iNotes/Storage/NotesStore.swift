import SwiftUI
import Combine

@MainActor
class NotesStore: ObservableObject {
    @Published var notes: [Note]
    @Published var selectedIndex: Int = 0
    @Published var showToolbar: Bool {
        didSet { UserDefaults.standard.set(showToolbar, forKey: "showToolbar") }
    }

    private let saveURL: URL
    private var saveCancellable: AnyCancellable?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("iNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.saveURL = dir.appendingPathComponent("notes.json")

        self.showToolbar = UserDefaults.standard.object(forKey: "showToolbar") as? Bool ?? true

        let decoder = Note.makeDecoder()

        if let data = try? Data(contentsOf: saveURL),
           let decoded = try? decoder.decode([Note].self, from: data) {
            // A validly-decoded file is never discarded for having any
            // particular count — that would silently destroy user content.
            self.notes = NotesStore.normalize(decoded)
        } else {
            // No file, or it could not be decoded at all — start fresh.
            self.notes = (1...3).map { Note(title: "Note \($0)") }
        }
        self.notes = NotesStore.pinnedFirst(self.notes)

        saveCancellable = $notes
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
    }

    /// Test-only initializer: no disk I/O and no debounced-save pipeline, so
    /// unit tests can drive the mutation methods without reading from or
    /// writing to the real `notes.json`.
    init(notesForTesting notes: [Note]) {
        self.saveURL = URL(fileURLWithPath: "/dev/null")
        self.showToolbar = true
        self.notes = notes
    }

    /// Normalize a decoded notes array WITHOUT discarding user content: a
    /// brand-new/empty file becomes a single fresh note so the app never has
    /// zero tabs, but any nonzero count of existing notes is kept as-is.
    static func normalize(_ decoded: [Note]) -> [Note] {
        guard decoded.isEmpty else { return decoded }
        return [Note(title: "Note 1")]
    }

    /// Stable-partition pinned notes to the front, preserving relative order
    /// within the pinned and unpinned groups.
    static func pinnedFirst(_ notes: [Note]) -> [Note] {
        notes.sorted { $0.isPinned && !$1.isPinned }
    }

    func save() {
        let encoder = Note.makeEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(notes) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    func updateText(at index: Int, text: String) {
        guard index >= 0 && index < notes.count else { return }
        notes[index].text = text
        notes[index].lastModified = .now
    }

    /// The `id` of the currently-selected note, if `selectedIndex` is valid.
    private var selectedID: UUID? {
        notes.indices.contains(selectedIndex) ? notes[selectedIndex].id : nil
    }

    /// Re-point `selectedIndex` at `id`'s new position after a mutation. If
    /// `id` is nil (no prior selection) or no longer present, falls back to
    /// `fallback`, clamped to valid bounds.
    private func restoreSelection(id: UUID?, fallback: Int) {
        if let id, let newIndex = notes.firstIndex(where: { $0.id == id }) {
            selectedIndex = newIndex
        } else {
            selectedIndex = max(0, min(fallback, notes.count - 1))
        }
    }

    func addNote() {
        let note = Note(title: "Note \(notes.count + 1)")
        notes.append(note)
        selectedIndex = notes.count - 1
    }

    func deleteNote(at index: Int) {
        guard notes.count > 1, notes.indices.contains(index) else { return }
        let id = selectedID
        notes.remove(at: index)
        restoreSelection(id: id, fallback: max(0, index - 1))
    }

    func deleteNote(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        deleteNote(at: index)
    }

    func moveNote(from source: Int, to destination: Int) {
        guard notes.indices.contains(source), destination >= 0, destination <= notes.count,
              source != destination else { return }
        let id = selectedID
        let note = notes.remove(at: source)
        let clampedDestination = min(destination, notes.count)
        notes.insert(note, at: clampedDestination)
        notes = NotesStore.pinnedFirst(notes)
        restoreSelection(id: id, fallback: selectedIndex)
    }

    func togglePin(at index: Int) {
        guard notes.indices.contains(index) else { return }
        let id = selectedID
        notes[index].isPinned.toggle()
        notes = NotesStore.pinnedFirst(notes)
        restoreSelection(id: id, fallback: selectedIndex)
    }
}
