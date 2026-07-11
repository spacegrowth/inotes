import AppKit

/// Draws list markers as pretty glyphs (`•`/`◦`/`▪`, `☐`/`☑`) and collapses the
/// redundant checkbox syntax to zero width — all without changing the source
/// characters. The saved text stays literal `- ` / `- [ ] ` / `- [x] ` markdown.
///
/// Two mechanisms:
/// 1. **Glyph hiding** (`NSLayoutManagerDelegate.shouldGenerateGlyphs`): every
///    range from `TextEditorLogic.hiddenSyntaxRanges` — checkbox ` [ ]`/` [x]`
///    syntax, the heading `#…# ` prefix, and complete inline `**`/`*`/`_`/`` ` ``
///    markers — is laid out as `.null` glyphs (not shown, zero advancement), so
///    the syntax vanishes live-preview style while the styled text stays. (This
///    also collapses the checkbox marker from six cells to one box + one space.)
/// 2. **Glyph substitution** (`drawGlyphs`): the single box/dash cell is painted
///    with the display glyph (checkboxes larger and vertically centered).
///
/// Bullets are a tight 1:1 dash→• swap and are not collapsed. Because layout for
/// bullet lines is untouched, their caret geometry is unchanged; checkbox lines
/// intentionally collapse the hidden syntax, so the caret visually skips it
/// (accepted, live-preview behavior).
final class MarkerLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {

    /// Crisp, fairly solid color for the box so it reads as a real checkbox
    /// (darker than the dimmed marker color used for bullets/inline syntax).
    static let boxColor = NSColor(white: 0.30, alpha: 1.0)

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    // MARK: - Glyph hiding (collapse checkbox syntax)

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let textStorage = textStorage else { return 0 }
        let ns = textStorage.string as NSString
        let count = glyphRange.length
        guard count > 0 else { return 0 }

        // Collect the absolute character ranges to hide within this batch.
        let firstChar = charIndexes[0]
        let lastChar = charIndexes[count - 1]
        let scan = NSRange(location: firstChar, length: lastChar - firstChar + 1)
        var hidden: [NSRange] = []
        var loc = scan.location
        let end = NSMaxRange(scan)
        while loc < end {
            let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            if para.length == 0 { break }
            let line = ns.substring(with: para).replacingOccurrences(of: "\n", with: "")
            // Checkbox syntax, heading prefix, and complete inline markers all
            // collapse to zero width in one pass.
            for r in TextEditorLogic.hiddenSyntaxRanges(forLine: line) {
                hidden.append(NSRange(location: para.location + r.location, length: r.length))
            }
            loc = NSMaxRange(para)
        }
        guard !hidden.isEmpty else { return 0 }

        // Mark the hidden characters' glyphs as `.null` (not shown, zero advance).
        let newProps = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: count)
        defer { newProps.deallocate() }
        var changed = false
        for i in 0..<count {
            var p = props[i]
            let ci = charIndexes[i]
            if hidden.contains(where: { NSLocationInRange(ci, $0) }) {
                p = .null
                changed = true
            }
            newProps[i] = p
        }
        guard changed else { return 0 }

        layoutManager.setGlyphs(glyphs, properties: newProps, characterIndexes: charIndexes,
                                font: aFont, forGlyphRange: glyphRange)
        return count
    }

    // MARK: - Glyph substitution (draw the pretty marker)

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage = textStorage,
              let container = textContainers.first,
              glyphsToShow.length > 0 else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        let ns = textStorage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        // Marker box/dash cells (and their substitute glyph) within this draw.
        var substitutions: [(glyphRange: NSRange, render: TextEditorLogic.MarkerRender)] = []
        var loc = charRange.location
        let charEnd = NSMaxRange(charRange)
        while loc < charEnd {
            let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            if para.length == 0 { break }
            let line = ns.substring(with: para).replacingOccurrences(of: "\n", with: "")
            if let m = TextEditorLogic.markerRender(forLine: line) {
                let absCharRange = NSRange(location: para.location + m.range.location,
                                           length: m.range.length)
                if NSIntersectionRange(absCharRange, charRange).length > 0 {
                    let gr = glyphRange(forCharacterRange: absCharRange, actualCharacterRange: nil)
                    substitutions.append((gr, m))
                }
            }
            loc = NSMaxRange(para)
        }

        guard !substitutions.isEmpty else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        substitutions.sort { $0.glyphRange.location < $1.glyphRange.location }

        // Draw literal glyphs for the gaps; paint the substitute over each cell.
        let showEnd = NSMaxRange(glyphsToShow)
        var cursor = glyphsToShow.location
        for (markerRange, render) in substitutions {
            let mStart = max(markerRange.location, glyphsToShow.location)
            let mEnd = min(NSMaxRange(markerRange), showEnd)
            if mStart >= mEnd { continue }
            if cursor < mStart {
                super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: mStart - cursor), at: origin)
            }
            drawMarker(render, glyphRange: NSRange(location: mStart, length: mEnd - mStart),
                       at: origin, container: container)
            cursor = mEnd
        }
        if cursor < showEnd {
            super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: showEnd - cursor), at: origin)
        }
    }

    /// Paint a single substitute glyph over the marker's cell. Bullets use the
    /// base font seated on the text baseline; checkboxes are drawn larger and
    /// vertically centered in the line so the box reads clean and crisp.
    private func drawMarker(_ render: TextEditorLogic.MarkerRender, glyphRange: NSRange,
                            at origin: NSPoint, container: NSTextContainer) {
        let cellRect = boundingRect(forGlyphRange: glyphRange, in: container)
        let glyph = render.glyph as NSString

        switch render.kind {
        case .bullet:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: defaultFont(),
                .foregroundColor: MarkdownStyler.markerColor
            ]
            glyph.draw(at: NSPoint(x: cellRect.minX + origin.x, y: cellRect.minY + origin.y),
                       withAttributes: attrs)

        case .checkbox:
            let lineRect = lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let box = Self.checkboxBoxRect(cellRect: cellRect, lineRect: lineRect)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Self.checkboxBoxFont,
                .foregroundColor: Self.boxColor
            ]
            glyph.draw(at: NSPoint(x: box.minX + origin.x, y: box.minY + origin.y), withAttributes: attrs)
        }
    }

    // MARK: - Checkbox box geometry (shared by drawing + hover cursor rect)

    /// Font the `☐`/`☑` box is drawn at — larger than the text so it reads crisp.
    static let checkboxBoxFont = NSFont.systemFont(ofSize: 16)

    /// The rect (in text-container coordinates, no container origin applied) the
    /// checkbox box glyph is painted into: anchored at the box cell's left edge
    /// and vertically centered in the line. Shared by `drawMarker` and
    /// `RichNoteTextView.cursorUpdate` so the hover target matches what's drawn.
    /// Pure given the cell and line rects.
    static func checkboxBoxRect(cellRect: NSRect, lineRect: NSRect) -> NSRect {
        let glyphSize = ("☐" as NSString).size(withAttributes: [.font: checkboxBoxFont])
        let x = cellRect.minX
        let y = lineRect.minY + (lineRect.height - glyphSize.height) / 2
        return NSRect(x: x, y: y, width: glyphSize.width, height: glyphSize.height)
    }
}
