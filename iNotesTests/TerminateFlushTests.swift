import XCTest
import AppKit
import SwiftUI
@testable import iNotes

/// Verifies the Cmd-Q data-loss fix: the `.iNotesFlushPendingEncode`
/// notification (posted from `applicationWillTerminate`) makes the editor
/// Coordinator flush its pending debounced RTF encode SYNCHRONOUSLY, so the
/// last <0.3s of typing reaches the store before `store.save()`.
@MainActor
final class TerminateFlushTests: XCTestCase {

    private final class DataBox { var data = Data() }

    func testTerminateNotificationFlushesPendingEncodeSynchronously() {
        let box = DataBox()
        let binding = Binding<Data>(get: { box.data }, set: { box.data = $0 })
        let view = NoteEditorView(rtfData: binding, noteID: UUID(), editorState: EditorState())
        let coordinator = view.makeCoordinator()
        coordinator.activeBinding = binding

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        textView.string = "hello world"

        // Simulate a keystroke: schedules the 0.3s debounced encode but does
        // not write the binding yet.
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertTrue(box.data.isEmpty, "Debounced encode must not write before the delay elapses")

        // The terminate flush must write the binding synchronously.
        NotificationCenter.default.post(name: .iNotesFlushPendingEncode, object: nil)

        XCTAssertFalse(box.data.isEmpty, "Terminate flush must persist the pending edit synchronously")
        let decoded = NSAttributedString(rtf: box.data, documentAttributes: nil)?.string
        XCTAssertEqual(decoded, "hello world", "Flushed RTF must contain the typed text")
    }
}
