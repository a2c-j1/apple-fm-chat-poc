import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct ChatAttachment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var fileName: String
    var filePath: String

    var url: URL { URL(fileURLWithPath: filePath) }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: MessageRole
    var content: String
    var attachments: [ChatAttachment]? = nil
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage] = []
    var updatedAt = Date()
}
