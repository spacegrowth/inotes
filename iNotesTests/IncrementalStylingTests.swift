import XCTest
import AppKit
@testable import iNotes

/// The editor restyles only the lines an edit touched (see
/// `NoteEditorView.Coordinator.pendingStyleRange`). These tests pin that this
/// always produces exactly the attributes a full-document restyle would, for
/// the edits most likely to break it: splitting and joining lines, lines that
/// change kind, and multi-line pastes.
@MainActor
final class IncrementalStylingTests: XCTestCase {

    private let base = """
    # Title
    - [ ] task **bold** and *italic*
    - bullet with `code`
    - [x] done item
    Plain paragraph with _underscored_ words.
    """

    /// Apply `edits` to a storage the way typing does — tracking the edited
    /// range through the Coordinator's storage delegate, then restyling only
    /// that range — and compare with a from-scratch full restyle.
    private func assertIncrementalMatchesFull(_ edits: [(NSRange, String)],
                                              file: StaticString = #filePath, line: UInt = #line) {
        let view = NoteEditorView(text: .constant(""), noteID: UUID(), editorState: EditorState())
        let coordinator = view.makeCoordinator()
        let incremental = NSTextStorage(string: base)
        MarkdownStyler.apply(to: incremental)
        incremental.delegate = coordinator

        for (range, replacement) in edits {
            incremental.replaceCharacters(in: range, with: replacement)
        }
        MarkdownStyler.apply(to: incremental,
                             in: coordinator.pendingStyleRange ?? NSRange(location: 0, length: incremental.length))

        let full = NSTextStorage(string: incremental.string)
        MarkdownStyler.apply(to: full)
        XCTAssertTrue(incremental.isEqual(to: full),
                      "incremental restyle diverged from full restyle for text:\n\(incremental.string)",
                      file: file, line: line)
    }

    private func range(of needle: String) -> NSRange { (base as NSString).range(of: needle) }

    func testTypingInsideALine() {
        assertIncrementalMatchesFull([(NSRange(location: range(of: "and").location, length: 0), "x")])
    }

    func testSplittingABoldSpanWithANewline() {
        let inBold = range(of: "bold").location + 2
        assertIncrementalMatchesFull([(NSRange(location: inBold, length: 0), "\n")])
    }

    func testJoiningTwoLines() {
        let newline = NSRange(location: NSMaxRange(range(of: "# Title")), length: 1)
        assertIncrementalMatchesFull([(newline, "")])
    }

    func testLineBecomesAHeading() {
        assertIncrementalMatchesFull([(NSRange(location: range(of: "Plain").location, length: 0), "## ")])
    }

    func testClosingAnItalicSpanOnALaterLine() {
        assertIncrementalMatchesFull([(NSRange(location: range(of: "code").location, length: 0), "*")])
    }

    func testMultiLinePasteAndSeveralEditsBeforeARestyle() {
        let paste = "new **line** one\n- [ ] new task\n### small"
        assertIncrementalMatchesFull([
            (NSRange(location: range(of: "done").location, length: 0), paste),
            (NSRange(location: 0, length: 2), ""),                    // drop "# " at the top
            (NSRange(location: range(of: "Title").location - 2, length: 0), "*"),
        ])
    }

    func testDeletingEverything() {
        assertIncrementalMatchesFull([(NSRange(location: 0, length: (base as NSString).length), "")])
    }
}
