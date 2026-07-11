import Foundation
import AppKit

/// A single note. The body is stored as **plain markdown source** (`text`);
/// the editor styles it live but never rewrites the characters, so what the
/// user sees round-trips losslessly to disk.
struct Note: Identifiable, Codable {
    let id: UUID
    var title: String
    var text: String
    var lastModified: Date
    var isPinned: Bool

    init(id: UUID = UUID(), title: String = "", text: String = "", lastModified: Date = .now, isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.text = text
        self.lastModified = lastModified
        self.isPinned = isPinned
    }

    enum CodingKeys: String, CodingKey {
        // `text` is the current format; `rtfData` / `content` are legacy inputs
        // that migrate on decode and are never re-emitted.
        case id, title, text, rtfData, content, lastModified, isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        // Old files predate pinning; default to unpinned so they still load.
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false

        if let markdown = try container.decodeIfPresent(String.self, forKey: .text) {
            // Current format: plain markdown source.
            text = markdown
        } else if let base64 = try container.decodeIfPresent(String.self, forKey: .rtfData),
                  let data = Data(base64Encoded: base64),
                  let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
            // Legacy RTF: flatten the attributed string to markdown so existing
            // users' notes survive the upgrade without data loss.
            text = Note.markdown(from: attr)
        } else if let plain = try container.decodeIfPresent(String.self, forKey: .content) {
            // Oldest legacy format: plain text stored under `content`.
            text = plain
        } else {
            text = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(text, forKey: .text)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(isPinned, forKey: .isPinned)
    }
}

// MARK: - RTF → markdown flattening (migration)

extension Note {
    /// Flatten a decoded RTF `NSAttributedString` into markdown source,
    /// preserving the structure the old editor encoded visually:
    /// `•`/`◦`/`▪` bullets → `- ` (nested by 2 spaces), `☐`/`☑` checkboxes →
    /// `- [ ] `/`- [x] `, heading-sized lines → `#`/`##`/`###`, and bold/italic
    /// runs → `**`/`*`. Everything else is kept as plain text.
    static func markdown(from attr: NSAttributedString) -> String {
        let ns = attr.string as NSString
        guard ns.length > 0 else { return "" }

        var result = ""
        var loc = 0
        while loc < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            // Split off a single trailing newline; RTF may also use \r or the
            // Unicode line/paragraph separators, so match any of them.
            var bodyLen = para.length
            if bodyLen > 0 {
                let last = ns.character(at: NSMaxRange(para) - 1)
                if last == 0x0A || last == 0x0D || last == 0x2028 || last == 0x2029 {
                    bodyLen -= 1
                }
            }
            let bodyRange = NSRange(location: para.location, length: bodyLen)
            result += flattenParagraph(attr, range: bodyRange)
            if bodyLen < para.length { result += "\n" }
            loc = NSMaxRange(para)
        }
        return result
    }

    private static func flattenParagraph(_ attr: NSAttributedString, range: NSRange) -> String {
        let ns = attr.string as NSString
        let line = ns.substring(with: range)

        // Structural prefixes the old editor stored as literal glyphs.
        let prefixMap: [(glyph: String, markdown: String)] = [
            ("☐ ", "- [ ] "),
            ("☑ ", "- [x] "),
            ("        ▪ ", "    - "), // level-3 bullet → 4-space indent
            ("    ◦ ", "  - "),        // level-2 bullet → 2-space indent
            ("• ", "- "),              // level-1 bullet
        ]
        for entry in prefixMap where line.hasPrefix(entry.glyph) {
            let glyphLen = (entry.glyph as NSString).length
            let contentRange = NSRange(location: range.location + glyphLen,
                                       length: range.length - glyphLen)
            return entry.markdown + inlineMarkdown(attr, range: contentRange)
        }

        // Heading: detected from the font size of the first character.
        if range.length > 0,
           let font = attr.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
            let level = TextEditorLogic.headingLevel(forFontSize: font.pointSize)
            if level > 0 {
                // Emit the heading prefix + plain text (whole line is already bold).
                return String(repeating: "#", count: level) + " " + line
            }
        }

        return inlineMarkdown(attr, range: range)
    }

    /// Walk the runs in `range` and wrap bold/italic runs in `**`/`*`.
    private static func inlineMarkdown(_ attr: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        let ns = attr.string as NSString
        var out = ""
        attr.enumerateAttribute(.font, in: range, options: []) { value, runRange, _ in
            let sub = ns.substring(with: runRange)
            guard !sub.trimmingCharacters(in: .whitespaces).isEmpty,
                  let font = value as? NSFont else {
                out += sub
                return
            }
            let traits = font.fontDescriptor.symbolicTraits
            var open = "", close = ""
            if traits.contains(.bold) { open += "**"; close = "**" + close }
            if traits.contains(.italic) { open += "*"; close = "*" + close }
            out += open + sub + close
        }
        return out
    }
}

// MARK: - Date strategy (sub-second precision + backward compatibility)

extension Note {
    /// ISO 8601 with fractional seconds — used for writing and read first on load.
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// ISO 8601 whole-second formatter — fallback so files written by the old
    /// `.iso8601` strategy (no fractional seconds) still decode.
    private static let iso8601WholeSecond: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Encoder that preserves sub-second `lastModified` precision.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601Fractional.string(from: date))
        }
        return encoder
    }

    /// Decoder that reads fractional-second timestamps and still accepts the
    /// legacy whole-second ISO 8601 strings from older saved files.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso8601Fractional.date(from: string)
                ?? iso8601WholeSecond.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(string)")
        }
        return decoder
    }
}
