import XCTest
@testable import iNotes

/// Tests for the `~/.inotes` folder model: one markdown file per tab, outside
/// edits picked up by `reloadFromDisk`, in-app edits written without
/// clobbering outside ones, and the one-time `notes.json` migration.
@MainActor
final class NotesFolderSyncTests: XCTestCase {

    private var root: URL!
    private var folder: NotesFolder!
    private var legacyURL: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesFolderSyncTests-\(UUID().uuidString)")
        folder = NotesFolder(url: root.appendingPathComponent("notes"))
        legacyURL = root.appendingPathComponent("legacy/notes.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() -> NotesStore {
        NotesStore(folder: folder, legacyJSONURL: legacyURL, watchForChanges: false)
    }

    private func write(_ text: String, _ name: String) {
        folder.createIfNeeded()
        XCTAssertTrue(folder.writeText(text, to: name))
    }

    // MARK: - Fresh start

    func testFreshFolder_startsWithOneNoteAndSavesItAsMarkdown() {
        let store = makeStore()
        XCTAssertEqual(store.notes.count, 1)
        store.updateText(at: 0, text: "hello")
        store.save()
        XCTAssertEqual(folder.readText("Note 1.md"), "hello")
        XCTAssertNotNil(NotesFolder.decodeIndex(folder.readIndexData()))
    }

    // MARK: - Outside edits

    func testOutsideEdit_replacesUnmodifiedNote() {
        write("one", "todo.md")
        let store = makeStore()
        XCTAssertEqual(store.notes.map(\.title), ["todo"])

        write("two", "todo.md")
        store.reloadFromDisk()
        XCTAssertEqual(store.notes[0].text, "two")
    }

    func testOutsideEdit_survivesInAppSaveOfAnotherNote() {
        write("a", "a.md")
        write("b", "b.md")
        let store = makeStore()

        write("b edited outside", "b.md")
        let aIndex = store.notes.firstIndex { $0.title == "a" }!
        store.updateText(at: aIndex, text: "a edited in app")
        store.save() // before the watcher reloads

        XCTAssertEqual(folder.readText("b.md"), "b edited outside",
                       "saving one note must not rewrite a file edited outside the app")
        XCTAssertEqual(folder.readText("a.md"), "a edited in app")
    }

    func testConflict_inAppTextWinsAndOutsideVersionIsParked() throws {
        write("base", "todo.md")
        let store = makeStore()

        store.updateText(at: 0, text: "in app")
        write("outside", "todo.md")
        store.reloadFromDisk()

        XCTAssertEqual(store.notes[0].text, "in app")
        let conflicts = folder.url.appendingPathComponent(NotesFolder.recoveredDirName)
        let parked = try FileManager.default.contentsOfDirectory(atPath: conflicts.path)
        XCTAssertEqual(parked.count, 1)
        XCTAssertEqual(try String(contentsOf: conflicts.appendingPathComponent(parked[0]), encoding: .utf8), "outside")

        store.save()
        XCTAssertEqual(folder.readText("todo.md"), "in app")
    }

    func testFileCreatedOutside_becomesATab() {
        write("x", "first.md")
        let store = makeStore()
        write("- [ ] ship it", "tasks.md")
        store.reloadFromDisk()
        XCTAssertEqual(store.notes.map(\.title), ["first", "tasks"])
        XCTAssertEqual(store.notes[1].text, "- [ ] ship it")
    }

    func testFileDeletedOutside_dropsTheTab() throws {
        write("x", "a.md")
        write("y", "b.md")
        let store = makeStore()
        try FileManager.default.removeItem(at: folder.fileURL("b.md"))
        store.reloadFromDisk()
        XCTAssertEqual(store.notes.map(\.title), ["a"])
    }

    func testReloadOfOwnWrite_isANoOp() {
        let store = makeStore()
        store.updateText(at: 0, text: "same")
        store.save()
        let before = store.notes.map(\.text)
        store.reloadFromDisk()
        XCTAssertEqual(store.notes.map(\.text), before)
    }

    // MARK: - Titles, order, pins

    func testRename_movesTheFile() {
        let store = makeStore()
        store.updateText(at: 0, text: "body")
        store.save()
        store.notes[0].title = "Groceries"
        store.save()
        XCTAssertEqual(folder.markdownFileNames(), ["Groceries.md"])
        XCTAssertEqual(folder.readText("Groceries.md"), "body")
    }

    func testCaseOnlyRename_keepsTheFileAndTheTab() {
        write("- EWY", "stocks.md")
        let store = makeStore()
        let id = store.notes[0].id
        store.notes[0].title = "Stocks"
        store.save()

        XCTAssertEqual(folder.markdownFileNames(), ["Stocks.md"])
        XCTAssertEqual(folder.readText("Stocks.md"), "- EWY")
        store.reloadFromDisk()
        XCTAssertEqual(store.notes.map(\.id), [id], "the renamed tab must survive the reload")
        XCTAssertEqual(store.notes[0].text, "- EWY")
    }

    func testSwappedTitles_keepEachNotesText() {
        write("alpha", "a.md")
        write("beta", "b.md")
        let store = makeStore()
        store.notes[0].title = "b"
        store.notes[1].title = "a"
        store.save()
        store.reloadFromDisk()
        XCTAssertEqual(store.notes.map(\.title), ["b", "a"])
        XCTAssertEqual(store.notes.map(\.text), ["alpha", "beta"])
    }

    func testFileDeletedOutside_parksItsTextInRecovered() throws {
        write("keep", "a.md")
        write("precious", "b.md")
        let store = makeStore()
        try FileManager.default.removeItem(at: folder.fileURL("b.md"))
        store.reloadFromDisk()
        let dir = folder.url.appendingPathComponent(NotesFolder.recoveredDirName)
        let parked = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(try parked.map { try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) },
                       ["precious"])
    }

    func testRelaunch_restoresOrderTitlesAndPins() {
        write("1", "one.md")
        write("2", "two.md")
        let store = makeStore()
        let twoIndex = store.notes.firstIndex { $0.title == "two" }!
        store.togglePin(at: twoIndex)
        store.notes[1].title = "One / renamed"
        store.save()

        let relaunched = makeStore()
        XCTAssertEqual(relaunched.notes.map(\.title), ["two", "One / renamed"])
        XCTAssertEqual(relaunched.notes.map(\.isPinned), [true, false])
        XCTAssertEqual(relaunched.notes.map(\.id), store.notes.map(\.id))
    }

    func testFileNames_areSanitizedAndUnique() {
        let notes = [Note(title: "a/b"), Note(title: "A-B"), Note(title: ".hidden"), Note(title: "  ")]
        let names = NotesFolder.assignFileNames(notes, current: [:])
        XCTAssertEqual(notes.map { names[$0.id]! }, ["a-b.md", "A-B 2.md", "hidden.md", "Untitled.md"])
    }

    // MARK: - Migration

    func testMigration_movesLegacyJSONIntoFolder() throws {
        let legacy = [
            Note(title: "todo", text: "- [ ] a", isPinned: true),
            Note(title: "scratch", text: "hello"),
        ]
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Note.makeEncoder().encode(legacy).write(to: legacyURL)

        let store = makeStore()

        XCTAssertEqual(store.notes.map(\.id), legacy.map(\.id))
        XCTAssertEqual(store.notes.map(\.text), ["- [ ] a", "hello"])
        XCTAssertEqual(store.notes.map(\.isPinned), [true, false])
        XCTAssertEqual(folder.readText("todo.md"), "- [ ] a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.appendingPathExtension("migrated").path))
    }

    func testMigration_neverRunsOverAnExistingFolder() throws {
        write("keep me", "mine.md")
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Note.makeEncoder().encode([Note(title: "old", text: "old")]).write(to: legacyURL)

        let store = makeStore()
        XCTAssertEqual(store.notes.map(\.title), ["mine"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    }
}
