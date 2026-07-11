import XCTest
import AppKit
@testable import iNotes

/// Tests for the model layer under the **markdown-source** model: `Note`
/// Codable round-trip (plain `text`), migration from legacy RTF and legacy
/// plain-text `content`, the date strategy, and the `NotesStore.normalize`
/// no-data-loss guard.
final class NoteModelTests: XCTestCase {

    private func makeEncoder() -> JSONEncoder { Note.makeEncoder() }
    private func makeDecoder() -> JSONDecoder { Note.makeDecoder() }

    // MARK: - Codable round-trip (plain text)

    func testNote_textRoundTrip_preservesIdTitleAndText() throws {
        let id = UUID()
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000) // whole second
        let original = Note(id: id, title: "My Note",
                            text: "# Heading\n- [ ] task\n- bullet",
                            lastModified: date)

        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(Note.self, from: data)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.title, "My Note")
        XCTAssertEqual(decoded.text, "# Heading\n- [ ] task\n- bullet")
        XCTAssertEqual(decoded.lastModified, date)
    }

    func testNote_encodesTextKey_notRtfOrContent() throws {
        let note = Note(title: "t", text: "plain markdown")
        let data = try makeEncoder().encode(note)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["text"] as? String, "plain markdown", "body persists as plain text")
        XCTAssertNil(json["rtfData"], "legacy RTF key must not be emitted")
        XCTAssertNil(json["content"], "legacy plain-text key must not be re-emitted")
    }

    func testNote_dateRoundTrip_subsecondPrecision() throws {
        let frac = Date(timeIntervalSinceReferenceDate: 700_000_000.5)
        let note = Note(title: "t", text: "x", lastModified: frac)
        let data = try makeEncoder().encode(note)
        let decoded = try makeDecoder().decode(Note.self, from: data)
        XCTAssertEqual(decoded.lastModified, frac, "sub-second precision should survive a round-trip")
    }

    func testNote_decodes_legacyWholeSecondISO8601String() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Old",
          "text": "hello",
          "lastModified": "2001-09-09T01:46:40Z"
        }
        """.data(using: .utf8)!

        let decoded = try makeDecoder().decode(Note.self, from: json)
        XCTAssertEqual(decoded.lastModified, Date(timeIntervalSince1970: 1_000_000_000),
                       "legacy whole-second ISO 8601 must still decode")
        XCTAssertEqual(decoded.text, "hello")
    }

    // MARK: - Migration: legacy RTF → markdown

    /// Build RTF from an attributed string for migration fixtures.
    private func rtf(_ attr: NSAttributedString) -> Data {
        (try? attr.data(from: NSRange(location: 0, length: attr.length),
                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }

    private func decodeNote(rtfBase64: String, id: UUID = UUID()) throws -> Note {
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Legacy",
          "rtfData": "\(rtfBase64)",
          "lastModified": "2026-01-02T03:04:05Z"
        }
        """.data(using: .utf8)!
        return try makeDecoder().decode(Note.self, from: json)
    }

    func testNote_legacyRTF_plainText_migratesToText() throws {
        let attr = NSAttributedString(string: "just plain text",
                                      attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let decoded = try decodeNote(rtfBase64: rtf(attr).base64EncodedString())
        XCTAssertEqual(decoded.text, "just plain text")
    }

    func testNote_legacyRTF_bullets_migrateToDashMarkdown() throws {
        // The old editor stored bullets as literal • / ◦ / ▪ glyphs.
        let attr = NSAttributedString(string: "• one\n    ◦ two\n        ▪ three",
                                      attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let decoded = try decodeNote(rtfBase64: rtf(attr).base64EncodedString())
        XCTAssertEqual(decoded.text, "- one\n  - two\n    - three")
    }

    func testNote_legacyRTF_checkboxes_migrateToTaskMarkdown() throws {
        let attr = NSAttributedString(string: "☐ todo\n☑ done",
                                      attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let decoded = try decodeNote(rtfBase64: rtf(attr).base64EncodedString())
        XCTAssertEqual(decoded.text, "- [ ] todo\n- [x] done")
    }

    func testNote_legacyRTF_heading_migratesToHashMarkdown() throws {
        let m = NSMutableAttributedString(string: "Title\nbody",
                                          attributes: [.font: NSFont.systemFont(ofSize: 13)])
        // Make the first line heading-sized (h1 ≥ 20pt).
        m.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 22),
                       range: (m.string as NSString).range(of: "Title"))
        let decoded = try decodeNote(rtfBase64: rtf(m).base64EncodedString())
        XCTAssertEqual(decoded.text, "# Title\nbody")
    }

    func testNote_legacyRTF_boldRun_migratesToStars() throws {
        let m = NSMutableAttributedString(string: "a bold word",
                                          attributes: [.font: NSFont.systemFont(ofSize: 13)])
        m.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13),
                       range: (m.string as NSString).range(of: "bold"))
        let decoded = try decodeNote(rtfBase64: rtf(m).base64EncodedString())
        XCTAssertEqual(decoded.text, "a **bold** word")
    }

    func testNote_legacyContentKey_migratesAsPlainText() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Legacy",
          "content": "old plain text",
          "lastModified": "2026-01-02T03:04:05Z"
        }
        """.data(using: .utf8)!
        let decoded = try makeDecoder().decode(Note.self, from: json)
        XCTAssertEqual(decoded.text, "old plain text")
    }

    func testNote_missingBody_fallsBackToEmpty() throws {
        let id = UUID()
        let json = """
        { "id": "\(id.uuidString)", "title": "Empty", "lastModified": "2026-01-02T03:04:05Z" }
        """.data(using: .utf8)!
        let decoded = try makeDecoder().decode(Note.self, from: json)
        XCTAssertEqual(decoded.text, "")
    }

    func testNote_invalidBase64Rtf_fallsBackToContent() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Bad",
          "rtfData": "!!! not base64 !!!",
          "content": "recovered text",
          "lastModified": "2026-01-02T03:04:05Z"
        }
        """.data(using: .utf8)!
        let decoded = try makeDecoder().decode(Note.self, from: json)
        XCTAssertEqual(decoded.text, "recovered text")
    }

    // MARK: - NotesStore.normalize (no data loss)

    func testStore_decode_threeNotesIsValid() throws {
        let notes = (1...3).map { Note(title: "Note \($0)", text: "body \($0)") }
        let data = try makeEncoder().encode(notes)
        let decoded = try makeDecoder().decode([Note].self, from: data)
        XCTAssertEqual(decoded.count, 3)
    }

    @MainActor
    func testStore_decode_nonEmptyCounts_normalizesWithoutDataLoss() throws {
        for count in [1, 2, 3, 4, 5] {
            let original = (0..<count).map { Note(title: "N\($0)", text: "body \($0)") }
            let data = try makeEncoder().encode(original)
            let decoded = try makeDecoder().decode([Note].self, from: data)
            XCTAssertEqual(decoded.count, count)

            let normalized = NotesStore.normalize(decoded)
            XCTAssertEqual(normalized.count, count,
                           "normalize never pads or trims a non-empty decoded file")
            for note in original {
                let survivor = normalized.first { $0.id == note.id }
                XCTAssertNotNil(survivor, "note \(note.title) must be preserved")
                XCTAssertEqual(survivor?.text, note.text)
            }
        }
    }

    @MainActor
    func testStore_decode_emptyFile_normalizesToOneFreshNote() throws {
        let normalized = NotesStore.normalize([])
        XCTAssertEqual(normalized.count, 1, "an empty/new file must still yield at least one note")
    }

    // MARK: - isPinned migration

    func testNote_oldFileWithoutIsPinned_decodesAsUnpinned() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Old",
          "text": "hello",
          "lastModified": "2001-09-09T01:46:40Z"
        }
        """.data(using: .utf8)!
        let decoded = try makeDecoder().decode(Note.self, from: json)
        XCTAssertFalse(decoded.isPinned, "notes.json files predating pinning must default to unpinned")
    }

    func testNote_isPinned_roundTrips() throws {
        let note = Note(title: "t", text: "x", isPinned: true)
        let data = try makeEncoder().encode(note)
        let decoded = try makeDecoder().decode(Note.self, from: data)
        XCTAssertTrue(decoded.isPinned)
    }
}
