import XCTest
import AppKit
import SwiftUI
@testable import iNotes

/// Verifies the Cmd-Q data-loss fix under the markdown-source model: the
/// `.iNotesFlushPendingEncode` notification (posted from
/// `applicationWillTerminate`) makes the editor Coordinator flush its pending
/// debounced save SYNCHRONOUSLY, so the last <0.3s of typing reaches the store
/// before `store.save()`. The body is now the plain markdown string.
@MainActor
final class TerminateFlushTests: XCTestCase {

    private final class TextBox { var text = "" }

    func testTerminateNotificationFlushesPendingSaveSynchronously() {
        let box = TextBox()
        let binding = Binding<String>(get: { box.text }, set: { box.text = $0 })
        let view = NoteEditorView(text: binding, noteID: UUID(), editorState: EditorState())
        let coordinator = view.makeCoordinator()
        coordinator.activeBinding = binding

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        textView.string = "hello world"

        // Simulate a keystroke: schedules the 0.3s debounced save but does not
        // write the binding yet.
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertTrue(box.text.isEmpty, "Debounced save must not write before the delay elapses")

        // The terminate flush must write the binding synchronously.
        NotificationCenter.default.post(name: .iNotesFlushPendingEncode, object: nil)

        XCTAssertEqual(box.text, "hello world",
                       "Terminate flush must persist the pending edit synchronously")
    }
}
