import XCTest
import AppKit
@testable import iNotes

/// Tests for the model layer: `Note` Codable round-trip (RTF base64 + legacy
/// plain-text migration) and the `NotesStore` `decoded.count == 3` decode guard.
final class NoteModelTests: XCTestCase {

    private func makeEncoder() -> JSONEncoder {
        Note.makeEncoder() // matches NotesStore.save()
    }

    private func makeDecoder() -> JSONDecoder {
        Note.makeDecoder() // matches NotesStore.init()
    }

    /// Extract the plain string from RTF data for assertions.
    private func plainText(of rtf: Data) -> String? {
        NSAttributedString(rtf: rtf, documentAttributes: nil)?.string
    }

    // MARK: - Codable round-trip (RTF base64)

    func testNote_rtfRoundTrip_preservesIdTitleAndRTF() throws {
        let id = UUID()
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000) // whole second
        let original = Note(id: id, title: "My Note",
                            rtfData: rtf(for: "Hello world"),
                            lastModified: date)

        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(Note.self, from: data)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.title, "My Note")
        XCTAssertEqual(decoded.rtfData, original.rtfData)
        XCTAssertEqual(plainText(of: decoded.rtfData), "Hello world")
        XCTAssertEqual(decoded.lastModified, date)
    }

    func testNote_encodesRtfDataKey_notContentKey() throws {
        let note = Note(title: "t", rtfData: rtf(for: "x"))
        let data = try makeEncoder().encode(note)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["rtfData"], "must persist base64 rtfData")
        XCTAssertNil(json["content"], "legacy plain-text key must not be re-emitted")
    }

    func testNote_dateRoundTrip_subsecondPrecision() throws {
        // FIXED — NotesStore now writes fractional-second ISO 8601, so
        // `lastModified` survives a round-trip with sub-second precision and two
        // edits within the same second remain distinguishable by timestamp.
        let frac = Date(timeIntervalSinceReferenceDate: 700_000_000.5)
        let note = Note(title: "t", rtfData: rtf(for: "x"), lastModified: frac)
        let data = try makeEncoder().encode(note)
        let decoded = try makeDecoder().decode(Note.self, from: data)
        XCTAssertEqual(decoded.lastModified, frac,
                       "sub-second precision should survive a round-trip")
    }

    func testNote_decodes_legacyWholeSecondISO8601String() throws {
        // BACKWARD COMPATIBILITY — files written by the old `.iso8601` strategy
        // store whole-second timestamps (no fractional part). They must still
        // decode under the new fractional-aware decoder.
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Old",
          "rtfData": "\(rtf(for: "legacy").base64EncodedString())",
          "lastModified": "2001-09-09T01:46:40Z"
        }
        """.data(using: .utf8)!

        let decoded = try makeDecoder().decode(Note.self, from: json)
        // 2001-09-09T01:46:40Z == 1_000_000_000 seconds since the 1970 epoch.
        XCTAssertEqual(decoded.lastModified,
                       Date(timeIntervalSince1970: 1_000_000_000),
                       "legacy whole-second ISO 8601 must still decode")
        XCTAssertEqual(plainText(of: decoded.rtfData), "legacy")
    }

    // MARK: - Legacy plain-text migration path

    func testNote_legacyContentKey_migratesToRTF() throws {
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
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.title, "Legacy")
        XCTAssertEqual(plainText(of: decoded.rtfData), "old plain text",
                       "legacy content must be migrated into rtfData")
    }

    func testNote_missingBothRtfAndContent_fallsBackToEmptyRTF() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Empty",
          "lastModified": "2026-01-02T03:04:05Z"
        }
        """.data(using: .utf8)!

        let decoded = try makeDecoder().decode(Note.self, from: json)
        XCTAssertEqual(decoded.title, "Empty")
        XCTAssertEqual(plainText(of: decoded.rtfData), "")
    }

    func testNote_invalidBase64RtfData_fallsBack() throws {
        // rtfData present but not valid base64 -> should not crash; falls through.
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
        // CHARACTERIZATION: invalid base64 falls through to the legacy content path.
        XCTAssertEqual(plainText(of: decoded.rtfData), "recovered text")
    }

    // MARK: - NotesStore decode-fallback guard (`decoded.count == 3`)

    func testStore_decode_threeNotesIsValid() throws {
        let notes = (1...3).map { Note(title: "Note \($0)", rtfData: rtf(for: "body \($0)")) }
        let data = try makeEncoder().encode(notes)
        let decoded = try makeDecoder().decode([Note].self, from: data)
        XCTAssertEqual(decoded.count, 3, "the exactly-3 case the store accepts")
    }

    @MainActor
    func testStore_decode_nonThreeCounts_normalizesWithoutDataLoss() throws {
        // A validly-decoded file is no longer discarded for having a count other
        // than 3. `NotesStore.normalize` pads short files up to the 3-tab baseline
        // and keeps any extras, so no user-authored note is ever dropped.
        for count in [0, 1, 2, 4, 5] {
            let original = (0..<count).map { Note(title: "N\($0)", rtfData: rtf(for: "body \($0)")) }
            let data = try makeEncoder().encode(original)
            let decoded = try makeDecoder().decode([Note].self, from: data)
            XCTAssertEqual(decoded.count, count, "decode of \(count) notes succeeds")

            let normalized = NotesStore.normalize(decoded)
            XCTAssertEqual(normalized.count, max(count, 3),
                           "normalize pads up to 3 but never trims content")
            // Every originally-saved note survives unchanged (no data loss).
            for note in original {
                let survivor = normalized.first { $0.id == note.id }
                XCTAssertNotNil(survivor, "note \(note.title) must be preserved")
                XCTAssertEqual(plainText(of: survivor!.rtfData), plainText(of: note.rtfData))
            }
        }
    }

    // MARK: - Helpers

    private func rtf(for string: String) -> Data {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.black
        ]
        let s = NSAttributedString(string: string, attributes: attrs)
        return (try? s.data(from: NSRange(location: 0, length: s.length),
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }
}
