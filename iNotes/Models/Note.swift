import Foundation

struct Note: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String
    var lastModified: Date

    init(id: UUID = UUID(), title: String = "", content: String = "", lastModified: Date = .now) {
        self.id = id
        self.title = title
        self.content = content
        self.lastModified = lastModified
    }
}
