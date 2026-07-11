import XCTest
@testable import iNotes

/// Tests for `NotesStore`'s tab mutations: add, delete (min 1), reorder,
/// and pin — all of which must keep `selectedIndex` pointing at the same
/// note (tracked by `id`) across the mutation.
@MainActor
final class NotesStoreTests: XCTestCase {

    private func makeStore(titles: [String]) -> NotesStore {
        let store = NotesStore(notesForTesting: titles.map { Note(title: $0) })
        store.selectedIndex = 0
        return store
    }

    // MARK: - Add

    func testAddNote_appendsAndSelectsIt() {
        let store = makeStore(titles: ["A", "B"])
        store.addNote()
        XCTAssertEqual(store.notes.count, 3)
        XCTAssertEqual(store.selectedIndex, 2)
        XCTAssertEqual(store.notes[2].title, "Note 3")
    }

    func testAddNote_cappedAtMaxNotes() {
        let store = makeStore(titles: (1...NotesStore.maxNotes).map { "N\($0)" })
        XCTAssertFalse(store.canAddNote, "should not allow adding at the cap")
        store.addNote() // no-op at the cap
        XCTAssertEqual(store.notes.count, NotesStore.maxNotes, "must not exceed the cap")
    }

    // MARK: - Delete

    func testDeleteNote_removesAndKeepsSelectionOnSurvivingNote() {
        let store = makeStore(titles: ["A", "B", "C"])
        let bID = store.notes[1].id
        store.selectedIndex = 1 // "B" selected

        store.deleteNote(at: 0) // delete "A"

        XCTAssertEqual(store.notes.count, 2)
        XCTAssertEqual(store.notes[store.selectedIndex].id, bID, "selection should stay on B")
    }

    func testDeleteNote_deletingSelectedNote_fallsBackToPreviousTab() {
        let store = makeStore(titles: ["A", "B", "C"])
        store.selectedIndex = 1 // "B" selected

        store.deleteNote(at: 1) // delete the selected note itself

        XCTAssertEqual(store.notes.count, 2)
        XCTAssertEqual(store.notes.map(\.title), ["A", "C"])
        XCTAssertEqual(store.selectedIndex, 0, "should fall back to the previous tab")
    }

    func testDeleteNote_cannotDeleteLastNote() {
        let store = makeStore(titles: ["Only"])
        store.deleteNote(at: 0)
        XCTAssertEqual(store.notes.count, 1, "the last remaining note must never be deletable")
    }

    func testDeleteNote_byID_removesCorrectNote() {
        let store = makeStore(titles: ["A", "B", "C"])
        let bID = store.notes[1].id
        store.deleteNote(id: bID)
        XCTAssertEqual(store.notes.map(\.title), ["A", "C"])
    }

    // MARK: - Move / reorder

    func testMoveNote_reordersAndPreservesSelectionByID() {
        let store = makeStore(titles: ["A", "B", "C"])
        let aID = store.notes[0].id
        store.selectedIndex = 0 // "A" selected

        store.moveNote(from: 0, to: 2) // drag A to the end

        XCTAssertEqual(store.notes.map(\.title), ["B", "C", "A"])
        XCTAssertEqual(store.notes[store.selectedIndex].id, aID, "selection should follow the moved note")
    }

    // MARK: - Pin

    func testTogglePin_pinnedNoteFloatsToFront() {
        let store = makeStore(titles: ["A", "B", "C"])
        let cIndex = store.notes.firstIndex { $0.title == "C" }!

        store.togglePin(at: cIndex)

        XCTAssertTrue(store.notes[0].isPinned)
        XCTAssertEqual(store.notes[0].title, "C")
        XCTAssertEqual(store.notes.map(\.title), ["C", "A", "B"])
    }

    func testTogglePin_preservesSelectionAcrossReorder() {
        let store = makeStore(titles: ["A", "B", "C"])
        let bID = store.notes[1].id
        store.selectedIndex = 1 // "B" selected
        let cIndex = store.notes.firstIndex { $0.title == "C" }!

        store.togglePin(at: cIndex) // pinning C moves it in front of B

        XCTAssertEqual(store.notes[store.selectedIndex].id, bID, "pinning another tab must not lose current selection")
    }

    func testTogglePin_unpin_returnsToUnpinnedGroup() {
        let store = makeStore(titles: ["A", "B", "C"])
        let cIndex = store.notes.firstIndex { $0.title == "C" }!
        store.togglePin(at: cIndex)
        let newCIndex = store.notes.firstIndex { $0.title == "C" }!

        store.togglePin(at: newCIndex) // unpin

        XCTAssertFalse(store.notes.first { $0.title == "C" }!.isPinned)
    }

    func testPinnedFirst_isStableWithinEachGroup() {
        var notes = [
            Note(title: "A", isPinned: true),
            Note(title: "B", isPinned: false),
            Note(title: "C", isPinned: true),
            Note(title: "D", isPinned: false),
        ]
        notes = NotesStore.pinnedFirst(notes)
        XCTAssertEqual(notes.map(\.title), ["A", "C", "B", "D"])
    }
}
