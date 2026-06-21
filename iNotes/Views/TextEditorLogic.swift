import Foundation

/// Pure, dependency-free string logic for the rich text editor.
///
/// These helpers operate purely on `String`/`Int`/`CGFloat` so they can be
/// unit-tested without a live `NSTextView`. They intentionally mirror the
/// previous inline behavior of the view classes exactly.
enum TextEditorLogic {
    // MARK: - Bullet levels

    /// Bullet prefixes for each nesting level (max 3).
    static let bulletLevels: [(prefix: String, marker: String)] = [
        ("", "•"),          // Level 1: •
        ("    ", "◦"),      // Level 2:     ◦
        ("        ", "▪"),  // Level 3:         ▪
    ]

    /// Returns the bullet level (1-3) for a paragraph, or 0 if not a bullet line.
    ///
    /// A line counts as a bullet only when it carries the marker *and* its
    /// trailing space (e.g. "• "), matching `isBulletParagraph`. A bare marker
    /// with no trailing space ("•text") is not a bullet.
    static func bulletLevel(of paraText: String) -> Int {
        for (i, level) in bulletLevels.enumerated().reversed() {
            let fullPrefix = level.prefix + level.marker + " "
            if paraText.hasPrefix(fullPrefix) {
                return i + 1
            }
        }
        return 0
    }

    /// Returns the full prefix string (indent + marker + space) for a given level (1-based).
    static func bulletPrefix(for level: Int) -> String {
        guard level >= 1 && level <= bulletLevels.count else { return "" }
        let b = bulletLevels[level - 1]
        return b.prefix + b.marker + " "
    }

    /// Returns the length (in UTF-16 code units) of the bullet prefix for a given level.
    static func bulletPrefixLength(of paraText: String, level: Int) -> Int {
        guard level >= 1 && level <= bulletLevels.count else { return 0 }
        let b = bulletLevels[level - 1]
        return b.prefix.count + b.marker.utf16.count + 1 // +1 for space
    }

    /// Whether a paragraph begins with any bullet marker (any nesting level).
    static func isBulletParagraph(_ paraText: String) -> Bool {
        paraText.hasPrefix("• ") || paraText.hasPrefix("    ◦ ") || paraText.hasPrefix("        ▪ ")
    }

    /// Add a top-level "• " prefix to each non-empty line of a multi-line string.
    /// Idempotent: a line that already carries any bullet prefix is left untouched.
    static func addBulletPrefix(toMultilineText text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var newText = ""
        for (i, line) in lines.enumerated() {
            if !line.isEmpty && !isBulletParagraph(line) {
                newText += "• " + line
            } else {
                newText += line
            }
            if i < lines.count - 1 { newText += "\n" }
        }
        return newText
    }

    /// Remove any bullet prefix (deepest-first) from each line of a multi-line string.
    static func removeBulletPrefix(fromMultilineText text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var newText = ""
        for (i, line) in lines.enumerated() {
            var cleaned = line
            for level in ["        ▪ ", "    ◦ ", "• "] {
                if cleaned.hasPrefix(level) {
                    cleaned = String(cleaned.dropFirst(level.count))
                    break
                }
            }
            newText += cleaned
            if i < lines.count - 1 { newText += "\n" }
        }
        return newText
    }

    // MARK: - Todo prefixes

    /// Whether a paragraph begins with a todo checkbox prefix.
    static func isTodoParagraph(_ paraText: String) -> Bool {
        paraText.hasPrefix("☐ ") || paraText.hasPrefix("☑ ")
    }

    /// Add a "☐ " prefix to each non-empty line of a multi-line string.
    /// Idempotent: a line that already carries a todo prefix is left untouched.
    static func addTodoPrefix(toMultilineText text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var newText = ""
        for (i, line) in lines.enumerated() {
            if !line.isEmpty && !isTodoParagraph(line) {
                newText += "☐ " + line
            } else {
                newText += line
            }
            if i < lines.count - 1 { newText += "\n" }
        }
        return newText
    }

    /// Remove a "☐ "/"☑ " prefix from each line of a multi-line string.
    static func removeTodoPrefix(fromMultilineText text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var newText = ""
        for (i, line) in lines.enumerated() {
            var cleaned = line
            if cleaned.hasPrefix("☐ ") || cleaned.hasPrefix("☑ ") {
                cleaned = String(cleaned.dropFirst(2))
            }
            newText += cleaned
            if i < lines.count - 1 { newText += "\n" }
        }
        return newText
    }

    // MARK: - Auto bullet

    /// Whether a paragraph should be auto-converted from a freshly-typed "- "
    /// into a "• " bullet.
    ///
    /// Fires only when the paragraph is *exactly* "- " (ignoring a trailing
    /// newline) — i.e. the user just typed "- " at the start of an otherwise
    /// empty line. It must NOT fire on a line that already has content after the
    /// dash (e.g. "- alpha "), which would otherwise re-convert the leading dash
    /// whenever a space is typed anywhere on the line.
    static func shouldConvertDashToBullet(_ paraText: String) -> Bool {
        let trimmed = paraText.hasSuffix("\n") ? String(paraText.dropLast()) : paraText
        return trimmed == "- "
    }

    // MARK: - Headings

    /// Maps a font point size to a heading level raw value (0 = body, 1 = h1, 2 = h2, 3 = h3).
    static func headingLevel(forFontSize size: CGFloat) -> Int {
        if size >= 20 { return 1 }
        if size >= 16 { return 2 }
        if size >= 14.5 { return 3 }
        return 0
    }
}
