import XCTest
import AppKit
import Carbon.HIToolbox
@testable import iNotes

/// Every toolbar action has a keyboard shortcut. These send real key-down
/// events through `RichNoteTextView.performKeyEquivalent` and check the
/// resulting markdown source.
@MainActor
final class FormattingShortcutTests: XCTestCase {

    private var textView: RichNoteTextView!
    private var state: EditorState!
    private var savedFontSize: CGFloat = 0

    override func setUp() {
        savedFontSize = AppSettings.baseFontSize
        state = EditorState()
        textView = RichNoteTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.editorState = state
        state.textView = textView
    }

    override func tearDown() {
        AppSettings.baseFontSize = savedFontSize
    }

    private func load(_ text: String, caret: Int = 0, length: Int = 0) {
        textView.string = text
        textView.setSelectedRange(NSRange(location: caret, length: length))
        state.updateFromSelection()
    }

    @discardableResult
    private func press(_ keyCode: Int, _ chars: String, shift: Bool = false) -> Bool {
        var flags: NSEvent.ModifierFlags = [.command]
        if shift { flags.insert(.shift) }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     characters: chars, charactersIgnoringModifiers: chars,
                                     isARepeat: false, keyCode: UInt16(keyCode))!
        return textView.performKeyEquivalent(with: event)
    }

    func testBoldItalicUnderline_wrapSelection() {
        load("word", caret: 0, length: 4)
        XCTAssertTrue(press(kVK_ANSI_B, "b"))
        XCTAssertEqual(textView.string, "**word**")

        load("word", caret: 0, length: 4)
        press(kVK_ANSI_I, "i")
        XCTAssertEqual(textView.string, "*word*")

        load("word", caret: 0, length: 4)
        press(kVK_ANSI_U, "u")
        XCTAssertEqual(textView.string, "_word_")
    }

    func testCmdDigit_setsHeadingAndTogglesBackToBody() {
        load("Title")
        XCTAssertTrue(press(kVK_ANSI_2, "2"))
        XCTAssertEqual(textView.string, "## Title")
        press(kVK_ANSI_1, "1")
        XCTAssertEqual(textView.string, "# Title")
        press(kVK_ANSI_1, "1")
        XCTAssertEqual(textView.string, "Title", "same heading again returns to body text")
        press(kVK_ANSI_3, "3")
        XCTAssertEqual(textView.string, "### Title")
    }

    func testCmdShift8_togglesBulletList() {
        load("item")
        XCTAssertTrue(press(kVK_ANSI_8, "*", shift: true))
        XCTAssertEqual(textView.string, "- item")
        press(kVK_ANSI_8, "*", shift: true)
        XCTAssertEqual(textView.string, "item")
    }

    func testCmdShift9_togglesChecklist() {
        load("task")
        XCTAssertTrue(press(kVK_ANSI_9, "(", shift: true))
        XCTAssertEqual(textView.string, "- [ ] task")
        press(kVK_ANSI_9, "(", shift: true)
        XCTAssertEqual(textView.string, "task")
    }

    func testCmdEqualsAndMinus_changeFontSize() {
        AppSettings.baseFontSize = 13
        state.fontSize = 13
        load("x")
        XCTAssertTrue(press(kVK_ANSI_Equal, "="))
        XCTAssertEqual(state.fontSize, 14)
        press(kVK_ANSI_Minus, "-")
        press(kVK_ANSI_Minus, "-")
        XCTAssertEqual(state.fontSize, 12)
    }

    func testUnrelatedShortcuts_passThrough() {
        load("abc")
        XCTAssertFalse(press(kVK_ANSI_K, "k"))
        XCTAssertFalse(press(kVK_ANSI_B, "B", shift: true), "Cmd+Shift+B is not bold")
        XCTAssertEqual(textView.string, "abc")
    }
}
