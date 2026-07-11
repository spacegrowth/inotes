import AppKit
import SwiftUI

/// Heading levels surfaced to the toolbar. In the markdown-source model these
/// map to `#`/`##`/`###` line prefixes rather than font sizes.
enum HeadingLevel: Int, CaseIterable {
    case body = 0
    case h1 = 1
    case h2 = 2
    case h3 = 3
}

@MainActor
class EditorState: ObservableObject {
    weak var textView: NSTextView?

    @Published var isBold = false
    @Published var isItalic = false
    @Published var isUnderlined = false
    @Published var currentHeading: HeadingLevel = .body
    @Published var isBulletList = false
    @Published var isTodoItem = false
    @Published var fontSize: CGFloat = AppSettings.baseFontSize

    // MARK: - Font size (A− / A+)

    func increaseFontSize() { setFontSize(fontSize + 1) }
    func decreaseFontSize() { setFontSize(fontSize - 1) }

    /// Persist `newValue` (clamped) as the base font size and immediately
    /// restyle the open note so body text, headings, and the checkbox box
    /// all rescale live.
    func setFontSize(_ newValue: CGFloat) {
        let clamped = AppSettings.clamp(newValue)
        guard clamped != fontSize else { return }
        AppSettings.baseFontSize = clamped
        fontSize = clamped
        restyleCurrentNote()
    }

    private func restyleCurrentNote() {
        guard let textView = textView, let ts = textView.textStorage else { return }
        MarkdownStyler.apply(to: ts)
        textView.typingAttributes = NoteEditorView.defaultAttributes
        textView.needsDisplay = true
    }

    // MARK: - Selection → toolbar state

    func updateFromSelection() {
        guard let textView = textView, let ts = textView.textStorage else {
            resetState()
            return
        }
        let ns = ts.string as NSString
        let sel = textView.selectedRange()

        // Line-level markers.
        let line = ns.length > 0
            ? ns.substring(with: ns.paragraphRange(for: sel)).replacingOccurrences(of: "\n", with: "")
            : ""
        currentHeading = HeadingLevel(rawValue: TextEditorLogic.headingLevel(ofLine: line)) ?? .body
        isTodoItem = TextEditorLogic.checkbox(ofLine: line) != nil
        isBulletList = TextEditorLogic.bullet(ofLine: line) != nil

        // Inline markers at the caret.
        let spans = TextEditorLogic.inlineSpans(in: ns as String)
        let loc = min(sel.location, max(0, ns.length))
        func inSpan(_ kind: TextEditorLogic.InlineKind) -> Bool {
            spans.contains { $0.kind == kind && NSLocationInRange(loc, $0.fullRange) }
        }
        isBold = inSpan(.bold)
        isItalic = inSpan(.italic)
        // The markdown model has no distinct underline; Cmd+U wraps `_…_`, which
        // is styled as italic. Leave the underline indicator off.
        isUnderlined = false
    }

    private func resetState() {
        isBold = false; isItalic = false; isUnderlined = false
        currentHeading = .body; isBulletList = false; isTodoItem = false
    }

    // MARK: - Inline wrap (Cmd+B / I / U)

    func toggleBold() { wrap(with: "**") }
    func toggleItalic() { wrap(with: "*") }
    func toggleUnderline() { wrap(with: "_") }

    private func wrap(with marker: String) {
        guard let textView = textView, let ts = textView.textStorage else { return }
        let ns = ts.string as NSString
        let sel = textView.selectedRange()
        let markerLen = (marker as NSString).length

        // No selection: drop an empty pair and place the caret between them.
        if sel.length == 0 {
            let insertion = marker + marker
            replace(sel, with: insertion, in: textView, ts,
                    selection: NSRange(location: sel.location + markerLen, length: 0))
            updateFromSelection()
            return
        }

        let selected = ns.substring(with: sel)

        // Markers sitting just OUTSIDE the selection → unwrap them.
        if sel.location >= markerLen, NSMaxRange(sel) + markerLen <= ns.length {
            let before = ns.substring(with: NSRange(location: sel.location - markerLen, length: markerLen))
            let after = ns.substring(with: NSRange(location: NSMaxRange(sel), length: markerLen))
            if before == marker, after == marker {
                let outer = NSRange(location: sel.location - markerLen,
                                    length: sel.length + 2 * markerLen)
                replace(outer, with: selected, in: textView, ts,
                        selection: NSRange(location: outer.location, length: (selected as NSString).length))
                updateFromSelection()
                return
            }
        }

        // Otherwise toggle markers on the selected substring itself.
        let result = TextEditorLogic.toggleWrap(selection: selected, marker: marker)
        replace(sel, with: result.replacement, in: textView, ts,
                selection: NSRange(location: sel.location, length: (result.replacement as NSString).length))
        updateFromSelection()
    }

    // MARK: - Line prefixes (headings / bullets / checkboxes)

    func applyHeading(_ level: HeadingLevel) {
        mutateSelectedLines { line in
            let stripped = Self.stripHeading(line)
            if level == .body { return stripped }
            return String(repeating: "#", count: level.rawValue) + " " + stripped
        }
        updateFromSelection()
    }

    func toggleBulletList() {
        let add = !isBulletList
        mutateSelectedLines { line in
            let (indent, rest) = Self.splitIndent(line)
            if add {
                if rest.isEmpty { return line }
                return indent + "- " + Self.stripListMarker(rest)
            } else {
                return indent + Self.stripListMarker(rest)
            }
        }
        updateFromSelection()
    }

    func toggleTodo() {
        let add = !isTodoItem
        mutateSelectedLines { line in
            let (indent, rest) = Self.splitIndent(line)
            if add {
                if rest.isEmpty { return line }
                return indent + "- [ ] " + Self.stripListMarker(rest)
            } else {
                return indent + Self.stripListMarker(rest)
            }
        }
        updateFromSelection()
    }

    /// Toggle the `[ ]`/`[x]` box on the checkbox line that starts at `paraStart`.
    func toggleCheckboxAt(_ paraStart: Int) {
        guard let textView = textView, let ts = textView.textStorage else { return }
        let ns = ts.string as NSString
        let paraRange = ns.paragraphRange(for: NSRange(location: paraStart, length: 0))
        let line = ns.substring(with: paraRange).replacingOccurrences(of: "\n", with: "")
        guard let box = TextEditorLogic.checkbox(ofLine: line) else { return }

        let charLoc = paraRange.location + TextEditorLogic.checkboxToggleOffset(box)
        guard charLoc < ns.length else { return }
        let newChar = box.checked ? " " : "x"
        let sel = textView.selectedRange()
        replace(NSRange(location: charLoc, length: 1), with: newChar, in: textView, ts, selection: sel)
        updateFromSelection()
    }

    // MARK: - Mutation helpers

    /// Replace `range` with `string` through the undo-aware path, then restyle.
    private func replace(_ range: NSRange, with string: String,
                         in textView: NSTextView, _ ts: NSTextStorage, selection: NSRange) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        ts.replaceCharacters(in: range, with: string)
        let clamped = NSRange(location: min(selection.location, ts.length),
                              length: min(selection.length, max(0, ts.length - selection.location)))
        textView.setSelectedRange(clamped)
        textView.didChangeText()
    }

    /// Apply a per-line transform across every line touched by the selection.
    private func mutateSelectedLines(_ transform: (String) -> String) {
        guard let textView = textView, let ts = textView.textStorage else { return }
        let ns = ts.string as NSString
        let sel = textView.selectedRange()
        let para = ns.length > 0 ? ns.paragraphRange(for: sel) : NSRange(location: 0, length: 0)
        let block = ns.substring(with: para)
        let hadTrailingNewline = block.hasSuffix("\n")
        let core = hadTrailingNewline ? String(block.dropLast()) : block
        let newCore = core.components(separatedBy: "\n").map(transform).joined(separator: "\n")
        let newBlock = hadTrailingNewline ? newCore + "\n" : newCore
        replace(para, with: newBlock, in: textView, ts,
                selection: NSRange(location: para.location, length: (newBlock as NSString).length))
    }

    // MARK: - Pure line editing helpers

    static func splitIndent(_ line: String) -> (indent: String, rest: String) {
        let n = TextEditorLogic.leadingSpaces(of: line)
        let ns = line as NSString
        return (ns.substring(to: n), ns.substring(from: n))
    }

    /// Remove a leading `- `, `* ` or `- [ ] `/`- [x] ` marker from a line whose
    /// indentation has already been split off (i.e. `rest` has no leading spaces).
    static func stripListMarker(_ rest: String) -> String {
        if let box = TextEditorLogic.checkbox(ofLine: rest) {
            return (rest as NSString).substring(from: box.markerRange.length)
        }
        if let b = TextEditorLogic.bullet(ofLine: rest) {
            return (rest as NSString).substring(from: b.markerRange.length)
        }
        return rest
    }

    static func stripHeading(_ line: String) -> String {
        let level = TextEditorLogic.headingLevel(ofLine: line)
        guard level > 0 else { return line }
        return (line as NSString).substring(from: TextEditorLogic.headingMarkerLength(level: level))
    }
}
