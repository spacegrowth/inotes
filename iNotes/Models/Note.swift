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
