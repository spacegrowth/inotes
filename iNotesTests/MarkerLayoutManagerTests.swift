import XCTest
import AppKit
@testable import iNotes

/// Verifies the glyph-substitution layout manager. Bullet lines keep byte-for-byte
/// identical layout to the stock manager (tight 1:1 dash→• swap, caret unchanged).
/// Checkbox lines intentionally collapse the ` [ ]` / ` [x]` syntax to zero-width
/// glyphs so the box renders as `☐ text` with no gap — here we assert the NEW
/// geometry (hidden glyphs carry zero advancement, content shifts left).
final class MarkerLayoutManagerTests: XCTestCase {

    private func makeStack(_ text: String, custom: Bool)
        -> (lm: NSLayoutManager, tc: NSTextContainer, ts: NSTextStorage) {
        let ts = NSTextStorage(string: text,
                               attributes: [.font: defaultFont(), .foregroundColor: NSColor.black])
        let lm: NSLayoutManager = custom ? MarkerLayoutManager() : NSLayoutManager()
        let tc = NSTextContainer(size: NSSize(width: 400, height: 200))
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        ts.addLayoutManager(lm)
        lm.ensureLayout(for: tc)
        return (lm, tc, ts)
    }

    /// Bullet and plain lines: every glyph sits at exactly the same location
    /// under the custom layout manager as under the stock one (no off-by-one).
    func testBulletAndPlainLayoutUnchanged() {
        for text in ["- item", "  - nested", "    - deep", "plain line"] {
            let stock = makeStack(text, custom: false)
            let custom = makeStack(text, custom: true)
            XCTAssertGreaterThan(stock.lm.numberOfGlyphs, 0, "layout produced glyphs for \(text)")
            XCTAssertEqual(custom.lm.numberOfGlyphs, stock.lm.numberOfGlyphs,
                           "glyph count must match for \(text)")
            for i in 0..<stock.lm.numberOfGlyphs {
                let ps = stock.lm.location(forGlyphAt: i)
                let pc = custom.lm.location(forGlyphAt: i)
                XCTAssertEqual(ps.x, pc.x, accuracy: 0.001, "glyph \(i) x for \(text)")
                XCTAssertEqual(ps.y, pc.y, accuracy: 0.001, "glyph \(i) y for \(text)")
            }
        }
    }

    /// Checkbox: the four `- [ ] ` syntax chars after the box collapse to zero
    /// advancement, so the box occupies one cell + one space and content butts up.
    func testCheckboxSyntaxCollapsesToZeroWidth() {
        let text = "- [ ] task"   // glyphs: 0='-'(box) 1=' ' 2='[' 3=' ' 4=']' 5=' ' 6...='task'
        let stock = makeStack(text, custom: false)
        let custom = makeStack(text, custom: true)
        XCTAssertEqual(custom.lm.numberOfGlyphs, stock.lm.numberOfGlyphs,
                       "hiding sets glyph properties, it does not remove glyphs")

        // Box cell (glyph 0) is unchanged at the line start.
        XCTAssertEqual(custom.lm.location(forGlyphAt: 0).x,
                       stock.lm.location(forGlyphAt: 0).x, accuracy: 0.001)

        // Hidden glyphs 1...4 have zero advancement: they, and the following
        // trailing-space glyph 5, all share the same x (the box's trailing edge).
        let xHidden = custom.lm.location(forGlyphAt: 1).x
        for i in 2...5 {
            XCTAssertEqual(custom.lm.location(forGlyphAt: i).x, xHidden, accuracy: 0.001,
                           "hidden glyph \(i) must carry zero advancement")
        }

        // The trailing space still advances, then content — so content sits ~2
        // cells in under the custom manager but ~6 cells in under the stock one.
        let customContentX = custom.lm.location(forGlyphAt: 6).x
        let stockContentX = stock.lm.location(forGlyphAt: 6).x
        XCTAssertGreaterThan(customContentX, xHidden, "content follows the trailing space")
        XCTAssertLessThan(customContentX, stockContentX - 1.0,
                          "checkbox content must collapse left vs the literal 6-cell marker")
    }

    /// The checkbox click hit-test must survive the collapse: a click on the
    /// on-screen box maps to a source offset *inside* the 6-char marker (so
    /// `RichNoteTextView.mouseDown` toggles), while a click on the content maps
    /// to the first content char (offset 6 → no toggle, caret placed instead).
    func testCheckboxClickHitTestAfterCollapse() {
        let text = "- [ ] task"
        let ts = NSTextStorage(string: text,
                               attributes: [.font: defaultFont(), .foregroundColor: NSColor.black])
        let lm = MarkerLayoutManager()
        let tc = NSTextContainer(size: NSSize(width: 400, height: 200))
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        ts.addLayoutManager(lm)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 60), textContainer: tc)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        lm.ensureLayout(for: tc)

        func offset(atGlyph i: Int) -> Int {
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: i, length: 1), in: tc)
            let point = NSPoint(x: rect.midX + tv.textContainerInset.width,
                                y: rect.midY + tv.textContainerInset.height)
            return tv.characterIndexForInsertion(at: point)
        }

        // Click on the box (glyph 0) → inside the marker → would toggle.
        XCTAssertLessThan(offset(atGlyph: 0), 6, "clicking the box must land inside the marker")
        // Click on the first content char (glyph 6, 't') → offset 6 → no toggle.
        XCTAssertGreaterThanOrEqual(offset(atGlyph: 6), 6, "clicking content must not toggle")
    }

    /// Heading `#…# ` prefix collapses to zero width, so the styled heading text
    /// starts at the left margin (content glyph shares x with the nulled hashes).
    func testHeadingPrefixCollapsesToZeroWidth() {
        let text = "# Title"   // glyphs: 0='#' 1=' ' 2='T'...
        let stock = makeStack(text, custom: false)
        let custom = makeStack(text, custom: true)
        XCTAssertEqual(custom.lm.numberOfGlyphs, stock.lm.numberOfGlyphs)
        // The two prefix glyphs are nulled: they and the first content glyph
        // all sit at the same (line-start) x.
        let x0 = custom.lm.location(forGlyphAt: 0).x
        XCTAssertEqual(custom.lm.location(forGlyphAt: 1).x, x0, accuracy: 0.001)
        XCTAssertEqual(custom.lm.location(forGlyphAt: 2).x, x0, accuracy: 0.001,
                       "heading text must start at the left margin")
        // Stock leaves `# ` visible, so its content sits ~2 cells in.
        XCTAssertGreaterThan(stock.lm.location(forGlyphAt: 2).x,
                             custom.lm.location(forGlyphAt: 2).x + 1.0)
    }

    /// Inline `**` markers collapse to zero width; the bold content shifts onto
    /// the marker's position.
    func testInlineBoldMarkersCollapseToZeroWidth() {
        let text = "a **b**"   // glyphs: 0='a' 1=' ' 2='*' 3='*' 4='b' 5='*' 6='*'
        let custom = makeStack(text, custom: true)
        // Open markers (glyphs 2,3) are nulled → they share x with content 'b' (4).
        let xOpen = custom.lm.location(forGlyphAt: 2).x
        XCTAssertEqual(custom.lm.location(forGlyphAt: 3).x, xOpen, accuracy: 0.001)
        XCTAssertEqual(custom.lm.location(forGlyphAt: 4).x, xOpen, accuracy: 0.001,
                       "bold content must sit where the hidden ** was")
        // Bold content still sits after "a " (~2 cells), not at the line start.
        XCTAssertGreaterThan(xOpen, 1.0)
    }

    /// The shared checkbox box rect (used by both drawing and the hover cursor
    /// rect) anchors at the cell's left edge and vertically centers the box in
    /// the line — so the hand cursor lands on the box the user sees.
    func testCheckboxBoxRect_anchoredAndVerticallyCentered() {
        let cell = NSRect(x: 10, y: 4, width: 8, height: 16)
        let line = NSRect(x: 0, y: 2, width: 300, height: 20)
        let box = MarkerLayoutManager.checkboxBoxRect(cellRect: cell, lineRect: line)

        XCTAssertEqual(box.minX, cell.minX, accuracy: 0.001, "box anchors at the cell's left edge")
        XCTAssertGreaterThan(box.width, 0)
        XCTAssertGreaterThan(box.height, 0)
        XCTAssertEqual(box.midY, line.midY, accuracy: 0.001, "box is vertically centered in the line")
    }

    /// The one box/dash cell the layout manager repaints lines up with the source
    /// dash. (On-screen glyph appearance is checked visually — see report.)
    func testMarkerRenderRangesMatchSourceCells() {
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "- item")?.range,
                       NSRange(location: 0, length: 1))
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "  - x")?.range,
                       NSRange(location: 2, length: 1))
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "- [ ] task")?.range,
                       NSRange(location: 0, length: 1))
        XCTAssertEqual(TextEditorLogic.markerRender(forLine: "    - [x] deep")?.range,
                       NSRange(location: 4, length: 1))
    }
}
