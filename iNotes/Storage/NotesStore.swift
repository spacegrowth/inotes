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
            // A validly-decoded file is never discarded for having a count other
            // than 3 — that would silently destroy user content. Normalize to the
            // 3-tab baseline by padding short files and keeping any extras.
            self.notes = NotesStore.normalize(decoded)
        } else {
            // No file, or it could not be decoded at all — start fresh.
            self.notes = (1...3).map { Note(title: "Note \($0)") }
        }

        saveCancellable = $notes
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
    }

    /// Normalize a decoded notes array to the app's 3-tab baseline WITHOUT
    /// discarding user content: pad short files up to 3 with fresh notes and
    /// keep any extra notes beyond 3 so nothing the user wrote is lost.
    static func normalize(_ decoded: [Note]) -> [Note] {
        guard decoded.count < 3 else { return decoded }
        var notes = decoded
        while notes.count < 3 {
            notes.append(Note(title: "Note \(notes.count + 1)"))
        }
        return notes
    }

    func save() {
        let encoder = Note.makeEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(notes) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    func updateRTFData(at index: Int, data: Data) {
        notes[index].rtfData = data
        notes[index].lastModified = .now
    }
}
