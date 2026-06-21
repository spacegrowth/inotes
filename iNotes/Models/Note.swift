import Foundation
import AppKit

struct Note: Identifiable, Codable {
    let id: UUID
    var title: String
    var rtfData: Data
    var lastModified: Date

    init(id: UUID = UUID(), title: String = "", rtfData: Data = Note.emptyRTFData(), lastModified: Date = .now) {
        self.id = id
        self.title = title
        self.rtfData = rtfData
        self.lastModified = lastModified
    }

    static func emptyRTFData() -> Data {
        let font = NSFont(name: "Menlo-Regular", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let attrStr = NSAttributedString(string: "", attributes: attrs)
        return (try? attrStr.data(from: NSRange(location: 0, length: 0),
                                  documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }

    enum CodingKeys: String, CodingKey {
        case id, title, rtfData, content, lastModified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        lastModified = try container.decode(Date.self, forKey: .lastModified)

        if let base64 = try container.decodeIfPresent(String.self, forKey: .rtfData),
           let data = Data(base64Encoded: base64) {
            // New RTF format
            rtfData = data
        } else if let plainText = try container.decodeIfPresent(String.self, forKey: .content) {
            // Old plain-text format — convert to RTF
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.black
            ]
            let attrStr = NSAttributedString(string: plainText, attributes: attrs)
            let range = NSRange(location: 0, length: attrStr.length)
            rtfData = (try? attrStr.data(from: range,
                                          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Note.emptyRTFData()
        } else {
            rtfData = Note.emptyRTFData()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(rtfData.base64EncodedString(), forKey: .rtfData)
        try container.encode(lastModified, forKey: .lastModified)
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
