import AppKit

/// Applies visual attributes over markdown source **without changing any
/// characters**. Runs on every edit (see `NoteEditorView.Coordinator`). The
/// text view's `string` stays the exact markdown that gets saved; this only
/// paints fonts/colors on top of it.
enum MarkdownStyler {

    // Marker glyphs are kept visible but dimmed so the source stays legible.
    static let markerColor = NSColor(white: 0.62, alpha: 1.0)
    static let codeColor = NSColor(calibratedRed: 0.55, green: 0.20, blue: 0.40, alpha: 1.0)
    static let checkedColor = NSColor.gray
    static let baseColor = NSColor.black

    /// Restyle the whole document. Cheap for scratchpad-sized notes; called
    /// synchronously after each change.
    static func apply(to textStorage: NSTextStorage) {
        let ns = textStorage.string as NSString
        let full = NSRange(location: 0, length: ns.length)

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        // 1. Reset every character to the plain base style.
        textStorage.setAttributes([
            .font: defaultFont(),
            .foregroundColor: baseColor
        ], range: full)

        guard ns.length > 0 else { return }

        // 2. Line pass — headings, checkboxes, bullets.
        ns.enumerateSubstrings(in: full, options: .byParagraphs) { sub, subRange, _, _ in
            guard let line = sub else { return }
            styleLine(line, at: subRange.location, in: textStorage)
        }

        // 3. Inline pass — bold / italic / code across the whole document.
        for span in TextEditorLogic.inlineSpans(in: ns as String) {
            styleInline(span, in: textStorage)
        }
    }

    // MARK: - Line styling

    private static func styleLine(_ line: String, at start: Int, in ts: NSTextStorage) {
        let lineRange = NSRange(location: start, length: (line as NSString).length)

        // Heading
        let hLevel = TextEditorLogic.headingLevel(ofLine: line)
        if hLevel > 0 {
            let size = TextEditorLogic.headingSizes(forBase: AppSettings.baseFontSize)[hLevel - 1]
            ts.addAttribute(.font, value: defaultBoldFont(size: size), range: lineRange)
            let markerLen = TextEditorLogic.headingMarkerLength(level: hLevel)
            ts.addAttribute(.foregroundColor, value: markerColor,
                            range: NSRange(location: start, length: markerLen))
            return
        }

        // Checkbox
        if let box = TextEditorLogic.checkbox(ofLine: line) {
            let markerRange = NSRange(location: start, length: box.markerRange.length)
            ts.addAttribute(.foregroundColor, value: markerColor, range: markerRange)
            if box.checked {
                let contentLen = lineRange.length - box.markerRange.length
                if contentLen > 0 {
                    let contentRange = NSRange(location: start + box.markerRange.length,
                                               length: contentLen)
                    ts.addAttribute(.strikethroughStyle,
                                    value: NSUnderlineStyle.single.rawValue, range: contentRange)
                    ts.addAttribute(.foregroundColor, value: checkedColor, range: contentRange)
                }
            }
            return
        }

        // Bullet
        if let b = TextEditorLogic.bullet(ofLine: line) {
            let markerRange = NSRange(location: start, length: b.markerRange.length)
            ts.addAttribute(.foregroundColor, value: markerColor, range: markerRange)
            return
        }
    }

    // MARK: - Inline styling

    private static func styleInline(_ span: TextEditorLogic.InlineSpan, in ts: NSTextStorage) {
        let content = span.contentRange
        guard content.length >= 0,
              NSMaxRange(span.fullRange) <= ts.length else { return }

        switch span.kind {
        case .bold:
            mergeTrait(.boldFontMask, over: content, in: ts)
        case .italic:
            mergeTrait(.italicFontMask, over: content, in: ts)
        case .code:
            ts.addAttribute(.foregroundColor, value: codeColor, range: content)
        }

        // Dim both markers.
        ts.addAttribute(.foregroundColor, value: markerColor, range: span.openMarkerRange)
        ts.addAttribute(.foregroundColor, value: markerColor, range: span.closeMarkerRange)
    }

    /// Add a bold/italic trait on top of whatever font a range already has
    /// (so `**bold in a ### heading**` keeps the larger heading size).
    private static func mergeTrait(_ trait: NSFontTraitMask, over range: NSRange, in ts: NSTextStorage) {
        guard range.length > 0 else { return }
        let manager = NSFontManager.shared
        ts.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let base = (value as? NSFont) ?? defaultFont()
            let converted = manager.convert(base, toHaveTrait: trait)
            ts.addAttribute(.font, value: converted, range: subRange)
        }
    }
}
