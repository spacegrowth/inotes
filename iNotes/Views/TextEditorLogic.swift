import Foundation

/// Pure, dependency-free string logic for the **markdown-source** editor.
///
/// Everything here operates on `String`/`NSString`/`Int` (Foundation only, no
/// AppKit) so it can be unit-tested without a live `NSTextView`. The editor's
/// `NSTextView.string` *is* the markdown source that gets saved; these helpers
/// parse that source into the line- and inline-level spans the styler paints
/// and the key handlers act on.
enum TextEditorLogic {

    // MARK: - Constants

    /// Number of spaces that make up one indentation level in the markdown source.
    static let indentUnit = 2

    /// Heading font point sizes for levels 1...3 (index 0 == h1).
    static let headingSizes: [CGFloat] = [22, 18, 15]

    // MARK: - Line: headings

    /// Heading level (1...3) for a line that starts with `# `, `## ` or `### `,
    /// or 0 when the line is not a heading. Requires the trailing space so a
    /// bare `#tag` is not treated as a heading.
    static func headingLevel(ofLine line: String) -> Int {
        var hashes = 0
        for ch in line {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard hashes >= 1 && hashes <= 3 else { return 0 }
        let idx = line.index(line.startIndex, offsetBy: hashes)
        guard idx < line.endIndex, line[idx] == " " else { return 0 }
        return hashes
    }

    /// UTF-16 length of the heading marker (`#`… + one space) for a level.
    static func headingMarkerLength(level: Int) -> Int { level + 1 }

    /// Map a font point size to a heading level (1 = h1, 2 = h2, 3 = h3,
    /// 0 = body). Used only when migrating legacy RTF, whose headings were
    /// encoded as font sizes rather than `#` markers.
    static func headingLevel(forFontSize size: CGFloat) -> Int {
        if size >= 20 { return 1 }
        if size >= 16 { return 2 }
        if size >= 14.5 { return 3 }
        return 0
    }

    // MARK: - Line: indentation

    /// Count of leading ASCII spaces on a line.
    static func leadingSpaces(of line: String) -> Int {
        var n = 0
        for ch in line {
            if ch == " " { n += 1 } else { break }
        }
        return n
    }

    // MARK: - Line: checkboxes

    /// A parsed checkbox line: `- [ ] ` / `- [x] ` after optional indentation.
    struct Checkbox: Equatable {
        /// Number of leading spaces before the marker.
        var indent: Int
        /// Whether the box is checked (`[x]`/`[X]`).
        var checked: Bool
        /// UTF-16 range of the full marker (indent spaces + `- [ ] `) within the line.
        var markerRange: NSRange
    }

    /// Parse a checkbox line, or `nil` if the line is not a checkbox.
    /// Accepts `-` or `*` as the list bullet and `[ ]`/`[x]`/`[X]`.
    static func checkbox(ofLine line: String) -> Checkbox? {
        let ns = line as NSString
        let indent = leadingSpaces(of: line)
        // Need at least "- [ ] " (6 chars) after the indentation.
        guard ns.length >= indent + 6 else { return nil }
        let marker = ns.substring(with: NSRange(location: indent, length: 6))
        let bullet = marker.first
        guard bullet == "-" || bullet == "*" else { return nil }
        let mchars = Array(marker)
        guard mchars[1] == " ", mchars[2] == "[", mchars[4] == "]", mchars[5] == " " else { return nil }
        let box = mchars[3]
        let checked: Bool
        if box == " " { checked = false }
        else if box == "x" || box == "X" { checked = true }
        else { return nil }
        return Checkbox(indent: indent, checked: checked,
                        markerRange: NSRange(location: 0, length: indent + 6))
    }

    /// UTF-16 offset within the line of the mutable box character (` ` or `x`)
    /// for a parsed checkbox — used by the click-to-toggle handler.
    static func checkboxToggleOffset(_ box: Checkbox) -> Int { box.indent + 3 }

    // MARK: - Line: bullets

    /// A parsed bullet line: `- ` / `* ` after optional indentation (NOT a checkbox).
    struct Bullet: Equatable {
        var indent: Int
        /// UTF-16 range of the full marker (indent spaces + `- `) within the line.
        var markerRange: NSRange
    }

    /// Parse a bullet list line, or `nil` if the line is not a plain bullet.
    /// Checkbox lines (`- [ ] `) return `nil` here — use `checkbox(ofLine:)`.
    static func bullet(ofLine line: String) -> Bullet? {
        if checkbox(ofLine: line) != nil { return nil }
        let ns = line as NSString
        let indent = leadingSpaces(of: line)
        guard ns.length >= indent + 2 else { return nil }
        let marker = ns.substring(with: NSRange(location: indent, length: 2))
        guard marker == "- " || marker == "* " else { return nil }
        return Bullet(indent: indent, markerRange: NSRange(location: 0, length: indent + 2))
    }

    // MARK: - Line: list editing (Enter / Tab / Shift-Tab)

    /// The prefix a *new* line should carry when Enter is pressed inside `line`,
    /// or `nil` when the line is not a list item. New checkbox items are always
    /// unchecked. Returns `nil` for an empty item (the caller should instead
    /// clear the marker — see `isEmptyListItem`).
    static func listContinuationPrefix(for line: String) -> String? {
        if let cb = checkbox(ofLine: line) {
            if isEmptyListItem(line) { return nil }
            return String(repeating: " ", count: cb.indent) + "- [ ] "
        }
        if let b = bullet(ofLine: line) {
            if isEmptyListItem(line) { return nil }
            return String(repeating: " ", count: b.indent) + "- "
        }
        return nil
    }

    /// Whether `line` is a list item (bullet or checkbox) whose content after the
    /// marker is empty or whitespace — i.e. pressing Enter should end the list.
    static func isEmptyListItem(_ line: String) -> Bool {
        let ns = line as NSString
        let markerLen: Int
        if let cb = checkbox(ofLine: line) { markerLen = cb.markerRange.length }
        else if let b = bullet(ofLine: line) { markerLen = b.markerRange.length }
        else { return false }
        guard ns.length >= markerLen else { return true }
        let rest = ns.substring(from: markerLen)
        return rest.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// UTF-16 length of the leading list marker (indent + `- ` / `- [ ] `),
    /// or 0 when the line is not a list item. Used to clear an empty item.
    static func listMarkerLength(of line: String) -> Int {
        if let cb = checkbox(ofLine: line) { return cb.markerRange.length }
        if let b = bullet(ofLine: line) { return b.markerRange.length }
        return 0
    }

    // MARK: - Inline spans (bold / italic / code)

    enum InlineKind: Equatable { case bold, italic, code }

    /// A styled inline run in the markdown source, in UTF-16 offsets relative to
    /// the string it was parsed from.
    struct InlineSpan: Equatable {
        var kind: InlineKind
        /// Full span including both markers.
        var fullRange: NSRange
        /// Length of one marker (`` ` `` = 1, `*`/`_` = 1, `**` = 2).
        var markerLength: Int

        var contentRange: NSRange {
            NSRange(location: fullRange.location + markerLength,
                    length: fullRange.length - 2 * markerLength)
        }
        var openMarkerRange: NSRange {
            NSRange(location: fullRange.location, length: markerLength)
        }
        var closeMarkerRange: NSRange {
            NSRange(location: NSMaxRange(fullRange) - markerLength, length: markerLength)
        }
    }

    // Compiled once. Character classes exclude newlines so spans never cross lines.
    private static let codeRegex = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
    private static let boldRegex = try! NSRegularExpression(pattern: "\\*\\*([^*\\n]+)\\*\\*")
    private static let italicStarRegex =
        try! NSRegularExpression(pattern: "(?<![*\\w])\\*(?!\\*)([^*\\n]+?)\\*(?!\\*)")
    private static let italicUnderscoreRegex =
        try! NSRegularExpression(pattern: "(?<![\\w_])_(?!_)([^_\\n]+?)_(?![\\w_])")

    /// Parse all inline bold/italic/code spans in `text`, returned in document
    /// order with absolute UTF-16 ranges. Overlaps resolve code > bold > italic.
    static func inlineSpans(in text: String) -> [InlineSpan] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var spans: [InlineSpan] = []

        func overlaps(_ r: NSRange) -> Bool {
            for s in spans where NSIntersectionRange(s.fullRange, r).length > 0 { return true }
            return false
        }
        func collect(_ regex: NSRegularExpression, kind: InlineKind, markerLength: Int) {
            for m in regex.matches(in: text, range: full) {
                if overlaps(m.range) { continue }
                spans.append(InlineSpan(kind: kind, fullRange: m.range, markerLength: markerLength))
            }
        }

        collect(codeRegex, kind: .code, markerLength: 1)
        collect(boldRegex, kind: .bold, markerLength: 2)
        collect(italicStarRegex, kind: .italic, markerLength: 1)
        collect(italicUnderscoreRegex, kind: .italic, markerLength: 1)

        spans.sort { $0.fullRange.location < $1.fullRange.location }
        return spans
    }

    // MARK: - Cmd+B/I/U wrap/unwrap

    /// Result of toggling a wrap marker around a selection.
    struct WrapResult: Equatable {
        /// The characters to substitute for `selection` (with or without markers).
        var replacement: String
        /// Whether the operation removed existing markers (true) or added them.
        var removed: Bool
    }

    /// Toggle `marker` (`**`, `*`, `_`, `` ` ``) around `selection`.
    /// If the selection is already wrapped in the marker, they are stripped;
    /// otherwise the selection is wrapped.
    static func toggleWrap(selection: String, marker: String) -> WrapResult {
        if selection.hasPrefix(marker), selection.hasSuffix(marker),
           selection.count >= 2 * marker.count {
            let inner = String(selection.dropFirst(marker.count).dropLast(marker.count))
            return WrapResult(replacement: inner, removed: true)
        }
        return WrapResult(replacement: marker + selection + marker, removed: false)
    }
}
