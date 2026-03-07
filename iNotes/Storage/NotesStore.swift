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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: saveURL),
           let decoded = try? decoder.decode([Note].self, from: data),
           decoded.count == 3 {
            self.notes = decoded
        } else {
            self.notes = (1...3).map { Note(title: "Note \($0)") }
        }

        saveCancellable = $notes
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
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
