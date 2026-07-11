import XCTest
import CoreGraphics
@testable import iNotes

/// Tests for `TextEditorLogic` — the pure markdown-source parsing layer that
/// drives live styling, list editing (Enter/Tab), and the Cmd+B/I/U wrap.
final class TextEditorLogicTests: XCTestCase {

    // MARK: - Headings

    func testHeadingLevel_detectsHashPrefixes() {
        XCTAssertEqual(TextEditorLogic.headingLevel(ofLine: "# h1"), 1)
        XCTAssertEqual(TextEditorLogic.headingLevel(ofLine: "## h2"), 2)
        XCTAssertEqual(TextEditorLogic.headingLevel(ofLine: "### h3"), 3)
    }

    func testHeadingLevel_requiresTrailingSpaceAndCaps() {
        XCTAssertEqual(TextEditorLogic.headingLevel(ofLine: "#tag"), 0, "no space → not a heading")
        XCTAssertEqual(TextEditorLogic.headingLevel(ofLine: "#### too deep"), 0)
        XCTAssertEqual(TextEditorLogic.headingLevel(ofLine: "plain"), 0)
        XCTAssertEqual(TextEditorLogic.headingLevel(ofLine: "#"), 0)
    }

    func testHeadingMarkerLength() {
        XCTAssertEqual(TextEditorLogic.headingMarkerLength(level: 1), 2) // "# "
        XCTAssertEqual(TextEditorLogic.headingMarkerLength(level: 3), 4) // "### "
    }

    // MARK: - Indentation

    func testLeadingSpaces() {
        XCTAssertEqual(TextEditorLogic.leadingSpaces(of: "no indent"), 0)
        XCTAssertEqual(TextEditorLogic.leadingSpaces(of: "  two"), 2)
        XCTAssertEqual(TextEditorLogic.leadingSpaces(of: "    four"), 4)
    }

    // MARK: - Checkboxes

    func testCheckbox_unchecked() {
        let box = TextEditorLogic.checkbox(ofLine: "- [ ] task")
        XCTAssertEqual(box, TextEditorLogic.Checkbox(indent: 0, checked: false,
                                                     markerRange: NSRange(location: 0, length: 6)))
    }

    func testCheckbox_checked_bothCases() {
        XCTAssertEqual(TextEditorLogic.checkbox(ofLine: "- [x] done")?.checked, true)
        XCTAssertEqual(TextEditorLogic.checkbox(ofLine: "- [X] done")?.checked, true)
    }

    func testCheckbox_indented() {
        let box = TextEditorLogic.checkbox(ofLine: "    - [ ] nested")
        XCTAssertEqual(box?.indent, 4)
        XCTAssertEqual(box?.markerRange, NSRange(location: 0, length: 10))
    }

    func testCheckbox_starBulletAccepted() {
        XCTAssertNotNil(TextEditorLogic.checkbox(ofLine: "* [ ] task"))
    }

    func testCheckbox_rejectsNonCheckbox() {
        XCTAssertNil(TextEditorLogic.checkbox(ofLine: "- bullet"))
        XCTAssertNil(TextEditorLogic.checkbox(ofLine: "plain"))
        XCTAssertNil(TextEditorLogic.checkbox(ofLine: "- [z] bad"))
        XCTAssertNil(TextEditorLogic.checkbox(ofLine: "- []"))
    }

    func testCheckboxToggleOffset() {
        let box = TextEditorLogic.checkbox(ofLine: "  - [ ] x")!
        XCTAssertEqual(TextEditorLogic.checkboxToggleOffset(box), 5) // indent(2) + 3
    }

    // MARK: - Bullets

    func testBullet_detectsDashAndStar() {
        XCTAssertEqual(TextEditorLogic.bullet(ofLine: "- item")?.markerRange,
                       NSRange(location: 0, length: 2))
        XCTAssertEqual(TextEditorLogic.bullet(ofLine: "* item")?.markerRange,
                       NSRange(location: 0, length: 2))
    }

    func testBullet_indented() {
        let b = TextEditorLogic.bullet(ofLine: "  - nested")
        XCTAssertEqual(b?.indent, 2)
        XCTAssertEqual(b?.markerRange, NSRange(location: 0, length: 4))
    }

    func testBullet_checkboxIsNotAPlainBullet() {
        XCTAssertNil(TextEditorLogic.bullet(ofLine: "- [ ] task"),
                     "a checkbox line must not also parse as a plain bullet")
    }

    func testBullet_rejectsNonBullet() {
        XCTAssertNil(TextEditorLogic.bullet(ofLine: "-no space"))
        XCTAssertNil(TextEditorLogic.bullet(ofLine: "plain"))
    }

    // MARK: - List continuation (Enter)

    func testListContinuation_bullet() {
        XCTAssertEqual(TextEditorLogic.listContinuationPrefix(for: "- item"), "- ")
        XCTAssertEqual(TextEditorLogic.listContinuationPrefix(for: "  - nested"), "  - ")
    }

    func testListContinuation_checkboxAlwaysUnchecked() {
        XCTAssertEqual(TextEditorLogic.listContinuationPrefix(for: "- [ ] a"), "- [ ] ")
        XCTAssertEqual(TextEditorLogic.listContinuationPrefix(for: "- [x] done"), "- [ ] ",
                       "continuing a checked item starts a fresh unchecked box")
        XCTAssertEqual(TextEditorLogic.listContinuationPrefix(for: "    - [ ] deep"), "    - [ ] ")
    }

    func testListContinuation_emptyItemReturnsNil() {
        XCTAssertNil(TextEditorLogic.listContinuationPrefix(for: "- "))
        XCTAssertNil(TextEditorLogic.listContinuationPrefix(for: "- [ ] "))
        XCTAssertNil(TextEditorLogic.listContinuationPrefix(for: "plain text"))
    }

    func testIsEmptyListItem() {
        XCTAssertTrue(TextEditorLogic.isEmptyListItem("- "))
        XCTAssertTrue(TextEditorLogic.isEmptyListItem("  - [ ] "))
        XCTAssertFalse(TextEditorLogic.isEmptyListItem("- x"))
        XCTAssertFalse(TextEditorLogic.isEmptyListItem("plain"))
    }

    func testListMarkerLength() {
        XCTAssertEqual(TextEditorLogic.listMarkerLength(of: "- x"), 2)
        XCTAssertEqual(TextEditorLogic.listMarkerLength(of: "  - x"), 4)
        XCTAssertEqual(TextEditorLogic.listMarkerLength(of: "- [ ] x"), 6)
        XCTAssertEqual(TextEditorLogic.listMarkerLength(of: "plain"), 0)
    }

    // MARK: - Marker glyph substitution

    func testMarkerRender_bulletDepthGlyphs() {
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "- top"),
                       TextEditorLogic.MarkerRender(range: NSRange(location: 0, length: 1), glyph: "•", kind: .bullet))
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "  - mid"),
                       TextEditorLogic.MarkerRender(range: NSRange(location: 2, length: 1), glyph: "◦", kind: .bullet))
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "    - deep"),
                       TextEditorLogic.MarkerRender(range: NSRange(location: 4, length: 1), glyph: "▪", kind: .bullet))
    }

    func testMarkerRender_bulletDepthClampsBeyondThree() {
        // 6+ spaces still renders the deepest glyph, replacing just the dash.
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "      - x")?.glyph, "▪")
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "      - x")?.range,
                       NSRange(location: 6, length: 1))
    }

    func testMarkerRender_checkboxGlyphs() {
        // Checkbox now replaces only the ONE box cell (the dash); the rest of
        // `- [ ] ` is collapsed via checkboxHiddenRange.
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "- [ ] task"),
                       TextEditorLogic.MarkerRender(range: NSRange(location: 0, length: 1), glyph: "☐", kind: .checkbox))
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "- [x] done"),
                       TextEditorLogic.MarkerRender(range: NSRange(location: 0, length: 1), glyph: "☑", kind: .checkbox))
    }

    func testMarkerRender_indentedCheckbox() {
        // The box cell sits at the indent; length is 1 (collapse handles the rest).
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "    - [x] deep"),
                       TextEditorLogic.MarkerRender(range: NSRange(location: 4, length: 1), glyph: "☑", kind: .checkbox))
    }

    func testMarkerRender_starBulletAndCheckbox() {
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "* item")?.glyph, "•")
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "* [ ] item")?.glyph, "☐")
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "* item")?.kind, .bullet)
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "* [ ] item")?.kind, .checkbox)
    }

    func testMarkerRender_nonListLinesReturnNil() {
        XCTAssertNil(TextEditorLogic.markerRender(forLine: "plain text"))
        XCTAssertNil(TextEditorLogic.markerRender(forLine: "# heading"))
        XCTAssertNil(TextEditorLogic.markerRender(forLine: "-no space"))
        XCTAssertNil(TextEditorLogic.markerRender(forLine: ""))
    }

    // MARK: - Checkbox syntax collapse (hidden range)

    func testCheckboxHiddenRange_coversSyntaxAfterBox() {
        // ` [ ]` / ` [x]` (4 chars) after the box cell are hidden.
        XCTAssertEqual(TextEditorLogic.checkboxHiddenRange(forLine: "- [ ] task"),
                       NSRange(location: 1, length: 4))
        XCTAssertEqual(TextEditorLogic.checkboxHiddenRange(forLine: "- [x] done"),
                       NSRange(location: 1, length: 4))
    }

    func testCheckboxHiddenRange_indented() {
        XCTAssertEqual(TextEditorLogic.checkboxHiddenRange(forLine: "    - [ ] deep"),
                       NSRange(location: 5, length: 4))
    }

    func testCheckboxHiddenRange_nilForNonCheckbox() {
        XCTAssertNil(TextEditorLogic.checkboxHiddenRange(forLine: "- bullet"))
        XCTAssertNil(TextEditorLogic.checkboxHiddenRange(forLine: "plain"))
    }

    // MARK: - Hidden syntax ranges (headings + inline markers)

    private func hidden(_ line: String) -> Set<NSRange> {
        Set(TextEditorLogic.hiddenSyntaxRanges(forLine: line))
    }

    func testHiddenSyntax_headingPrefixEachLevel() {
        XCTAssertEqual(hidden("# Title"), [NSRange(location: 0, length: 2)])   // "# "
        XCTAssertEqual(hidden("## Sub"), [NSRange(location: 0, length: 3)])    // "## "
        XCTAssertEqual(hidden("### Deep"), [NSRange(location: 0, length: 4)])  // "### "
    }

    func testHiddenSyntax_bold() {
        // "a **bold** b": open `**` at 2, close `**` at 8.
        XCTAssertEqual(hidden("a **bold** b"),
                       [NSRange(location: 2, length: 2), NSRange(location: 8, length: 2)])
    }

    func testHiddenSyntax_italicStarAndUnderscore() {
        XCTAssertEqual(hidden("*i*"),
                       [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1)])
        XCTAssertEqual(hidden("_i_"),
                       [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1)])
    }

    func testHiddenSyntax_code() {
        // "`c`": backticks at 0 and 2.
        XCTAssertEqual(hidden("`c`"),
                       [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1)])
    }

    func testHiddenSyntax_unclosedMarkerNotHidden() {
        XCTAssertTrue(hidden("**bold").isEmpty, "half-typed bold must stay visible")
        XCTAssertTrue(hidden("*italic").isEmpty, "half-typed italic must stay visible")
        XCTAssertTrue(hidden("`code").isEmpty, "half-typed code must stay visible")
    }

    func testHiddenSyntax_boldInsideHeading() {
        // "# a **b**": heading prefix (0,2) + bold markers (4,2) and (7,2).
        XCTAssertEqual(hidden("# a **b**"),
                       [NSRange(location: 0, length: 2),
                        NSRange(location: 4, length: 2),
                        NSRange(location: 7, length: 2)])
    }

    func testHiddenSyntax_plainLineHasNone() {
        XCTAssertTrue(hidden("just plain text").isEmpty)
    }

    func testHiddenSyntax_checkboxSyntaxIncluded() {
        // Checkbox line still contributes its ` [ ]` hidden range through the
        // unified helper (the box cell itself is drawn, not hidden).
        XCTAssertEqual(hidden("- [ ] task"), [NSRange(location: 1, length: 4)])
    }

    // MARK: - Inline spans

    func testInline_bold() {
        let spans = TextEditorLogic.inlineSpans(in: "a **bold** b")
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans.first?.kind, .bold)
        XCTAssertEqual(spans.first?.fullRange, NSRange(location: 2, length: 8))
        XCTAssertEqual(spans.first?.contentRange, NSRange(location: 4, length: 4))
    }

    func testInline_italicStarAndUnderscore() {
        XCTAssertEqual(TextEditorLogic.inlineSpans(in: "an *italic* one").first?.kind, .italic)
        XCTAssertEqual(TextEditorLogic.inlineSpans(in: "an _italic_ one").first?.kind, .italic)
    }

    func testInline_code() {
        let spans = TextEditorLogic.inlineSpans(in: "call `foo()` now")
        XCTAssertEqual(spans.first?.kind, .code)
        XCTAssertEqual(spans.first?.markerLength, 1)
    }

    func testInline_boldNotMisreadAsTwoItalics() {
        let spans = TextEditorLogic.inlineSpans(in: "**b**")
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans.first?.kind, .bold)
    }

    func testInline_underscoreInsideWordIsNotItalic() {
        XCTAssertTrue(TextEditorLogic.inlineSpans(in: "snake_case_name").isEmpty,
                      "underscores inside a word must not become italic")
    }

    func testInline_multipleSpansSortedByLocation() {
        let spans = TextEditorLogic.inlineSpans(in: "`c` then **b** then *i*")
        XCTAssertEqual(spans.map(\.kind), [.code, .bold, .italic])
    }

    func testInline_markersDoNotCrossNewlines() {
        XCTAssertTrue(TextEditorLogic.inlineSpans(in: "*a\nb*").isEmpty,
                      "a marker pair split across lines must not match")
    }

    // MARK: - Wrap toggle (Cmd+B/I/U)

    func testToggleWrap_addsMarkers() {
        let r = TextEditorLogic.toggleWrap(selection: "text", marker: "**")
        XCTAssertEqual(r, TextEditorLogic.WrapResult(replacement: "**text**", removed: false))
    }

    func testToggleWrap_stripsWhenAlreadyWrapped() {
        let r = TextEditorLogic.toggleWrap(selection: "**text**", marker: "**")
        XCTAssertEqual(r, TextEditorLogic.WrapResult(replacement: "text", removed: true))
    }

    func testToggleWrap_italicMarker() {
        XCTAssertEqual(TextEditorLogic.toggleWrap(selection: "x", marker: "*").replacement, "*x*")
        XCTAssertEqual(TextEditorLogic.toggleWrap(selection: "*x*", marker: "*").replacement, "x")
    }

    // MARK: - RTF-migration heading size mapping

    func testHeadingLevel_forFontSize() {
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 22), 1)
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 18), 2)
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 15), 3)
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 13), 0)
    }

    // MARK: - Status footer: word / char counts

    func testWordCount_empty() {
        XCTAssertEqual(TextEditorLogic.wordCount(""), 0)
    }

    func testWordCount_whitespaceOnly() {
        XCTAssertEqual(TextEditorLogic.wordCount("   \n\t  \n"), 0)
    }

    func testWordCount_collapsesMultipleSpacesAndNewlines() {
        XCTAssertEqual(TextEditorLogic.wordCount("one   two\n\nthree\tfour"), 4)
    }

    func testWordCount_singleWord() {
        XCTAssertEqual(TextEditorLogic.wordCount("hello"), 1)
    }

    func testWordCount_unicodeWords() {
        // Emoji and accented/CJK characters each count as their own word when
        // whitespace-separated, same as any other token.
        XCTAssertEqual(TextEditorLogic.wordCount("café 日本語 🎉 naïve"), 4)
    }

    func testCharCount_empty() {
        XCTAssertEqual(TextEditorLogic.charCount(""), 0)
    }

    func testCharCount_whitespaceOnly() {
        XCTAssertEqual(TextEditorLogic.charCount("   "), 3)
    }

    func testCharCount_countsGraphemeClusters() {
        XCTAssertEqual(TextEditorLogic.charCount("hello"), 5)
        // A combined emoji (family: man, woman, girl, boy) is one grapheme
        // cluster despite being multiple unicode scalars.
        XCTAssertEqual(TextEditorLogic.charCount("👨‍👩‍👧‍👦"), 1)
    }

    func testCharCount_includesNewlinesAndSpaces() {
        XCTAssertEqual(TextEditorLogic.charCount("a b\nc"), 5)
    }
}
