import Foundation
import GRDB

/// The `message` row. Mirrors `ChatMessage` plus the two foreign-key/DB-only fields
/// (`chatID`, `isStreaming` as it was last persisted) that the in-memory model has no need for.
struct MessageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "message"

    var id: String
    var chatID: String
    var role: String
    var text: String
    var thinking: String
    var isStreaming: Bool
    var promptTokens: Int?
    var completionTokens: Int?
    var tokensPerSecond: Double?
    var createdAt: Date

    init(_ message: ChatMessage, chatID: UUID) {
        self.id = message.id.uuidString
        self.chatID = chatID.uuidString
        self.role = message.role.rawValue
        self.text = message.text
        self.thinking = message.thinking
        self.isStreaming = message.isStreaming
        self.promptTokens = nil
        self.completionTokens = nil
        self.tokensPerSecond = nil
        self.createdAt = message.createdAt
    }

    /// Fails only if the row was written by something other than this type — never in
    /// practice, since this is the only writer.
    func asChatMessage() -> ChatMessage? {
        guard let uuid = UUID(uuidString: id), let messageRole = MessageRole(rawValue: role) else {
            return nil
        }
        return ChatMessage(
            id: uuid,
            role: messageRole,
            text: text,
            thinking: thinking,
            isStreaming: isStreaming,
            createdAt: createdAt
        )
    }
}
