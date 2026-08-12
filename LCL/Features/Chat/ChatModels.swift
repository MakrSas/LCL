import Foundation

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    var text: String
    var thinking: String
    var isStreaming: Bool
    let createdAt: Date

    /// Each message owns its parser, which is what makes the incremental guarantee hold:
    /// settled blocks belong to this message and are never re-parsed.
    var parser = MarkdownParser()
    var blocks: [MarkdownBlock] = []

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String = "",
        thinking: String = "",
        isStreaming: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.thinking = thinking
        self.isStreaming = isStreaming
        self.createdAt = createdAt
        if !text.isEmpty {
            self.blocks = self.parser.blocks(for: text)
        }
    }

    mutating func append(_ delta: String) {
        text += delta
        blocks = parser.blocks(for: text)
    }

    mutating func reparse() {
        parser.reset()
        blocks = parser.blocks(for: text)
    }

    var hasThinking: Bool { !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
