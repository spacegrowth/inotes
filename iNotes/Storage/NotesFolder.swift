import Foundation

/// On-disk layout of the notes: one plain-markdown file per tab plus an
/// `index.json` holding what a bare file can't (tab order, pins, exact titles,
/// stable ids):
///
///     ~/.inotes/
///       index.json
///       todo.md
///       stocks.md
///
/// The folder is meant to be edited by other tools too (an editor, a script, a
/// Claude session). Any `*.md` file dropped in becomes a tab; editing one
/// updates the open tab live (see `NotesStore.reloadFromDisk`).
struct NotesFolder {
    let url: URL

    static let indexFileName = "index.json"
    static let recoveredDirName = ".recovered"

    /// `~/.inotes`. Under App Sandbox the home directory resolves to the app's
    /// container, so a sandboxed build transparently stays inside it.
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".inotes", isDirectory: true)
    }

    /// Pre-folder storage: a single JSON array of notes (see `Note` decoding).
    static var legacyJSONURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("iNotes", isDirectory: true)
            .appendingPathComponent("notes.json")
    }

    struct IndexEntry: Codable, Equatable {
        var id: UUID
        var file: String
        var title: String
        var isPinned: Bool
    }

    var indexURL: URL { url.appendingPathComponent(Self.indexFileName) }

    func fileURL(_ name: String) -> URL { url.appendingPathComponent(name) }

    func createIfNeeded() {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - Reading

    /// Names of the visible `*.md` files in the folder (hidden files skipped).
    func markdownFileNames() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && $0.lowercased().hasSuffix(".md") }.sorted()
    }

    func readText(_ name: String) -> String? {
        guard let data = try? Data(contentsOf: fileURL(name)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func modificationDate(_ name: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL(name).path))?[.modificationDate] as? Date
    }

    func readIndexData() -> Data? { try? Data(contentsOf: indexURL) }

    static func decodeIndex(_ data: Data?) -> [IndexEntry]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([IndexEntry].self, from: data)
    }

    // MARK: - Writing

    @discardableResult
    func writeText(_ text: String, to name: String) -> Bool {
        (try? Data(text.utf8).write(to: fileURL(name), options: .atomic)) != nil
    }

    static func encodeIndex(_ entries: [IndexEntry]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(entries)) ?? Data("[]".utf8)
    }

    /// Park text that would otherwise be gone for good: the losing side of a
    /// simultaneous edit, or a tab whose file was deleted outside the app.
    /// Hidden folder → it does not become a tab.
    func saveRecoveredCopy(_ text: String, of name: String) {
        let dir = url.appendingPathComponent(Self.recoveredDirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let stem = (name as NSString).deletingPathExtension
        try? Data(text.utf8).write(to: dir.appendingPathComponent("\(stem) \(stamp).md"), options: .atomic)
    }

    // MARK: - File names

    /// A safe file name for a tab title: path separators and `:` become `-`,
    /// leading dots are dropped (they would hide the file), empty → "Untitled".
    static func baseName(forTitle title: String) -> String {
        var name = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "Untitled" }
        return String(name.prefix(100))
    }

    /// Assign each note a unique file name derived from its title. A note keeps
    /// its current name when that name still matches its title, so unrelated
    /// saves never shuffle files around. `reserved` names are never handed
    /// out. Case-insensitive, like APFS.
    static func assignFileNames(_ notes: [Note], current: [UUID: String],
                                reserved: Set<String> = []) -> [UUID: String] {
        var result: [UUID: String] = [:]
        var taken = Set(reserved.map { $0.lowercased() })
        var pending: [Note] = []

        for note in notes {
            let base = baseName(forTitle: note.title)
            if let existing = current[note.id], matches(existing, base: base),
               !taken.contains(existing.lowercased()) {
                result[note.id] = existing
                taken.insert(existing.lowercased())
            } else {
                pending.append(note)
            }
        }
        for note in pending {
            let base = baseName(forTitle: note.title)
            var candidate = base + ".md"
            var n = 2
            while taken.contains(candidate.lowercased()) {
                candidate = "\(base) \(n).md"
                n += 1
            }
            result[note.id] = candidate
            taken.insert(candidate.lowercased())
        }
        return result
    }

    /// True if `fileName` is `base.md` or a de-duplicated `base N.md`.
    private static func matches(_ fileName: String, base: String) -> Bool {
        guard fileName.hasSuffix(".md") else { return false }
        let stem = String(fileName.dropLast(3))
        if stem == base { return true }
        guard stem.hasPrefix(base + " ") else { return false }
        return Int(stem.dropFirst(base.count + 1)) != nil
    }

    // MARK: - Migration

    /// One-time move from the legacy `notes.json` into this folder. Runs only
    /// when the folder holds no notes yet, so it can never clobber anything.
    /// The old file is renamed (not deleted) to `notes.json.migrated`.
    /// Returns true if a migration happened.
    @discardableResult
    func migrateLegacyJSONIfNeeded(from legacyURL: URL = NotesFolder.legacyJSONURL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyURL.path),
              !fm.fileExists(atPath: indexURL.path),
              markdownFileNames().isEmpty,
              let data = try? Data(contentsOf: legacyURL),
              let notes = try? Note.makeDecoder().decode([Note].self, from: data),
              !notes.isEmpty else { return false }

        createIfNeeded()
        let names = Self.assignFileNames(notes, current: [:])
        var entries: [IndexEntry] = []
        for note in notes {
            let name = names[note.id]!
            guard writeText(note.text, to: name) else { return false }
            try? fm.setAttributes([.modificationDate: note.lastModified], ofItemAtPath: fileURL(name).path)
            entries.append(IndexEntry(id: note.id, file: name, title: note.title, isPinned: note.isPinned))
        }
        guard (try? Self.encodeIndex(entries).write(to: indexURL, options: .atomic)) != nil else { return false }

        let moved = legacyURL.appendingPathExtension("migrated")
        try? fm.removeItem(at: moved)
        try? fm.moveItem(at: legacyURL, to: moved)
        return true
    }
}

// MARK: - Watching

/// FSEvents watcher for the notes folder. FSEvents (rather than a directory
/// `DispatchSource`) is required because many tools rewrite files in place,
/// which never touches the directory entry.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
