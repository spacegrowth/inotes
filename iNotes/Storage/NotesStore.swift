import SwiftUI
import Combine

@MainActor
class NotesStore: ObservableObject {
    /// A menu-bar scratchpad, not a file manager: cap the number of tabs so
    /// each stays visible/readable in the narrow panel. Pinned tabs count too.
    static let maxNotes = 5

    @Published var notes: [Note]
    @Published var selectedIndex: Int = 0
    @Published var showToolbar: Bool {
        didSet { UserDefaults.standard.set(showToolbar, forKey: "showToolbar") }
    }

    /// Where the notes live; `nil` for the in-memory test store.
    private let folder: NotesFolder?
    private var watcher: FolderWatcher?
    private var saveCancellable: AnyCancellable?

    /// The file each note is stored in.
    private var fileNames: [UUID: String] = [:]
    /// Each file's text as last read from or written to disk. This is the
    /// common base that tells an in-app edit (note text differs from it) apart
    /// from an outside edit (disk differs from it).
    private var syncedText: [String: String] = [:]
    /// `index.json` bytes as last read or written, to spot outside edits to it.
    private var syncedIndex: Data?

    init(folder: NotesFolder = NotesFolder(url: NotesFolder.defaultURL),
         legacyJSONURL: URL = NotesFolder.legacyJSONURL,
         watchForChanges: Bool = true) {
        self.folder = folder
        self.showToolbar = UserDefaults.standard.object(forKey: "showToolbar") as? Bool ?? true
        self.notes = []

        folder.createIfNeeded()
        folder.migrateLegacyJSONIfNeeded(from: legacyJSONURL)
        reloadFromDisk()

        saveCancellable = $notes
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }

        if watchForChanges {
            watcher = FolderWatcher(url: folder.url) { [weak self] in
                MainActor.assumeIsolated { self?.reloadFromDisk() }
            }
        }
    }

    /// Test-only initializer: no disk I/O and no debounced-save pipeline, so
    /// unit tests can drive the mutation methods without touching the real
    /// notes folder.
    init(notesForTesting notes: [Note]) {
        self.folder = nil
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

    // MARK: - Disk sync

    /// Pull outside changes to the notes folder into memory. Called at launch
    /// and whenever the folder changes (including echoes of our own writes,
    /// which are no-ops because they match `syncedText`).
    ///
    /// Per file: an outside edit replaces the note unless the note also has an
    /// unsaved in-app edit. In that race the in-app text wins and the outside
    /// version is parked in `.recovered/`, so neither is silently lost.
    func reloadFromDisk() {
        guard let folder else { return }
        // Land keystrokes still debounced in the editor first, so an in-flight
        // edit counts as unsaved below instead of being replaced.
        NotificationCenter.default.post(name: .iNotesFlushPendingEncode, object: nil)

        let diskFiles = Set(folder.markdownFileNames())
        let indexData = folder.readIndexData()
        let index = NotesFolder.decodeIndex(indexData) ?? []
        let selected = selectedID
        var result: [Note] = []

        // APFS is case-insensitive: `stocks.md` and `Stocks.md` are one file.
        let diskByLowercase = Dictionary(diskFiles.map { ($0.lowercased(), $0) },
                                         uniquingKeysWith: { first, _ in first })

        for var note in notes {
            guard var file = fileNames[note.id] else { result.append(note); continue }
            let base = syncedText[file]
            let hasUnsavedEdit = note.text != base
            guard let onDisk = diskByLowercase[file.lowercased()] else {
                // Deleted outside the app: drop the tab, unless it holds unsaved
                // text (then the next save recreates the file). Its last text is
                // parked in `.recovered/` so a deletion is never unrecoverable.
                if hasUnsavedEdit {
                    result.append(note)
                } else {
                    if !note.text.isEmpty { folder.saveRecoveredCopy(note.text, of: file) }
                    fileNames[note.id] = nil
                    syncedText[file] = nil
                }
                continue
            }
            if onDisk != file {
                // Only the case changed on disk: follow it rather than losing the tab.
                syncedText[onDisk] = syncedText.removeValue(forKey: file)
                fileNames[note.id] = onDisk
                file = onDisk
            }
            if let disk = folder.readText(file), disk != base {
                if hasUnsavedEdit {
                    folder.saveRecoveredCopy(disk, of: file)
                } else {
                    note.text = disk
                    note.lastModified = folder.modificationDate(file) ?? .now
                }
                syncedText[file] = disk
            }
            result.append(note)
        }

        // Files created outside the app become new tabs. At launch this is
        // every file; the index supplies their ids, titles and pins.
        let tracked = Set(fileNames.values)
        let takenIDs = Set(result.map(\.id))
        let indexByFile = Dictionary(index.map { ($0.file, $0) }, uniquingKeysWith: { first, _ in first })
        for file in diskFiles.subtracting(tracked).sorted() {
            guard let text = folder.readText(file) else { continue }
            let entry = indexByFile[file].flatMap { takenIDs.contains($0.id) ? nil : $0 }
            let note = Note(id: entry?.id ?? UUID(),
                            title: entry?.title ?? (file as NSString).deletingPathExtension,
                            text: text,
                            lastModified: folder.modificationDate(file) ?? .now,
                            isPinned: entry?.isPinned ?? false)
            fileNames[note.id] = file
            syncedText[file] = text
            result.append(note)
        }

        // An index edited outside the app (or read at launch) sets order,
        // titles and pins; otherwise the in-memory order stands.
        if indexData != syncedIndex {
            let byID = Dictionary(index.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let position = Dictionary(index.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for i in result.indices {
                if let entry = byID[result[i].id] {
                    result[i].title = entry.title
                    result[i].isPinned = entry.isPinned
                }
            }
            result = result.enumerated()
                .sorted { (position[$0.element.id] ?? .max, $0.offset) < (position[$1.element.id] ?? .max, $1.offset) }
                .map(\.element)
            syncedIndex = indexData
        }

        result = NotesStore.pinnedFirst(NotesStore.normalize(result))
        guard !NotesStore.sameContent(result, notes) else { return }
        notes = result
        restoreSelection(id: selected, fallback: selectedIndex)
    }

    /// Write in-app changes to the folder: only notes whose text or file name
    /// changed are written, so files edited outside the app are left alone.
    func save() {
        guard let folder else { return }
        folder.createIfNeeded()

        // Untracked files on disk (e.g. created outside the app a moment ago
        // and not reloaded yet) are never picked as a note's new file name.
        let untracked = Set(folder.markdownFileNames()).subtracting(fileNames.values)
        let names = NotesFolder.assignFileNames(notes, current: fileNames, reserved: untracked)

        for note in notes {
            let file = names[note.id]!
            var moved = false
            // Renamed tab: move its file. A case-only rename (stocks → Stocks)
            // must be a move, since on APFS both names are the same file and
            // writing the new one then retiring the old one deletes it.
            if let old = fileNames[note.id], old != file, let base = syncedText[old],
               old.lowercased() == file.lowercased()
                || !FileManager.default.fileExists(atPath: folder.fileURL(file).path),
               rename(folder.fileURL(old).path, folder.fileURL(file).path) == 0 {
                syncedText[old] = nil
                syncedText[file] = base
                moved = true
            }
            guard note.text != syncedText[file] || (fileNames[note.id] != file && !moved) else { continue }
            // Outside edit not reloaded yet: park it rather than overwrite it.
            if let base = syncedText[file], let disk = folder.readText(file), disk != base {
                folder.saveRecoveredCopy(disk, of: file)
            }
            if folder.writeText(note.text, to: file) {
                syncedText[file] = note.text
            }
        }

        // Retire files of deleted/renamed notes, unless edited outside the app
        // since we last saw them (the next reload then shows them as a tab).
        // A name that differs from a live one only by case is that live file.
        let live = Set(names.values)
        let liveLowercased = Set(live.map { $0.lowercased() })
        for (file, base) in syncedText where !live.contains(file) {
            if !liveLowercased.contains(file.lowercased()), folder.readText(file) == base {
                try? FileManager.default.removeItem(at: folder.fileURL(file))
            }
            syncedText[file] = nil
        }
        fileNames = names

        let entries = notes.map {
            NotesFolder.IndexEntry(id: $0.id, file: names[$0.id]!, title: $0.title, isPinned: $0.isPinned)
        }
        let data = NotesFolder.encodeIndex(entries)
        // SHORTCUT: index.json is last-writer-wins. An outside edit to it that
        // lands within the watcher's ~0.2s latency of an in-app save is lost
        // (note files are protected; order/pins/titles are not). Upgrade path:
        // re-read and diff the index here the way note files are checked above.
        if data != syncedIndex, (try? data.write(to: folder.indexURL, options: .atomic)) != nil {
            syncedIndex = data
        }
    }

    private static func sameContent(_ a: [Note], _ b: [Note]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.id == $1.id && $0.title == $1.title && $0.text == $1.text && $0.isPinned == $1.isPinned
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

    /// True when another tab can be added (below the cap).
    var canAddNote: Bool { notes.count < NotesStore.maxNotes }

    func addNote() {
        guard canAddNote else { return }
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
