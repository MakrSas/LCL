import Foundation
import GRDB

/// The whole persistence surface `ChatViewModel` needs, per the integration seam documented
/// in docs/PHASE_1_PLAN.md Step 2. An actor because GRDB's own guidance for `DatabaseQueue` is
/// to serialize access behind exactly one owner, matching `ModelProvider`'s "inference must
/// never touch the main actor" convention elsewhere in this codebase.
actor ChatStore {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Opens (or creates) the real on-disk database in Application Support.
    static func live() throws -> ChatStore {
        ChatStore(dbQueue: try AppDatabase.open())
    }

    // MARK: - Chats

    struct ChatSummary: Identifiable, Sendable, Equatable {
        var id: UUID
        var title: String
        var updatedAt: Date
    }

    /// "New Chat" per docs/PHASE_1_PLAN.md Step 2 point 5: creates a row and returns its id
    /// for the caller to switch `ChatViewModel` onto — never deletes existing history.
    @discardableResult
    func createChat(title: String = "New Chat") throws -> UUID {
        let id = UUID()
        let now = Date()
        try dbQueue.write { db in
            try ChatRecord(id: id.uuidString, title: title, createdAt: now, updatedAt: now).insert(db)
        }
        return id
    }

    /// For the sidebar's recent-chats list, newest first.
    func listChats() throws -> [ChatSummary] {
        try dbQueue.read { db in
            try ChatRecord
                .order(Column("updatedAt").desc)
                .fetchAll(db)
                .compactMap { record in
                    guard let id = UUID(uuidString: record.id) else { return nil }
                    return ChatSummary(id: id, title: record.title, updatedAt: record.updatedAt)
                }
        }
    }

    func deleteChat(_ chatID: UUID) throws {
        _ = try dbQueue.write { db in
            try ChatRecord.deleteOne(db, key: chatID.uuidString)
        }
    }

    // MARK: - Messages

    /// `ChatViewModel.init` per Step 2 point 1: loads a chat's existing messages instead of
    /// always starting empty. Ordered by `createdAt` so streamed history replays in order.
    func loadMessages(chatID: UUID) throws -> [ChatMessage] {
        try dbQueue.read { db in
            try MessageRecord
                .filter(Column("chatID") == chatID.uuidString)
                .order(Column("createdAt"))
                .fetchAll(db)
                .compactMap { $0.asChatMessage() }
        }
    }

    /// `ChatViewModel.send()` per Step 2 point 2: called immediately after appending to the
    /// in-memory array — for both the user message and the empty, `isStreaming: true`
    /// assistant placeholder — so a kill mid-request still leaves a resumable row.
    func insertMessage(_ message: ChatMessage, chatID: UUID) throws {
        try dbQueue.write { db in
            try MessageRecord(message, chatID: chatID).insert(db)
            try touch(chatID.uuidString, db: db)
        }
    }

    /// `ChatViewModel.finishStreaming()` per Step 2 points 3–4: the one write per turn, with
    /// the completed text, thinking, and usage. Never called from the ~16ms `flush()` timer.
    func finishMessage(
        _ messageID: UUID,
        text: String,
        thinking: String,
        usage: TokenUsage?
    ) throws {
        try dbQueue.write { db in
            guard var record = try MessageRecord.fetchOne(db, key: messageID.uuidString) else { return }
            record.text = text
            record.thinking = thinking
            record.isStreaming = false
            record.promptTokens = usage?.promptTokens
            record.completionTokens = usage?.completionTokens
            record.tokensPerSecond = usage?.tokensPerSecond
            try record.update(db)
            try touch(record.chatID, db: db)
        }
    }

    private func touch(_ chatID: String, db: Database) throws {
        try db.execute(sql: "UPDATE chat SET updatedAt = ? WHERE id = ?", arguments: [Date(), chatID])
    }

    // MARK: - Search

    struct SearchHit: Identifiable, Sendable, Equatable {
        var id: UUID
        var chatID: UUID
        var text: String
        var createdAt: Date
    }

    /// BM25-ranked full-text search over message content (docs/CONTEXT_ENGINE.md, "FTS5 / BM25
    /// over raw text"). `bm25()` returns more-negative for better matches, so ascending —
    /// SQLite's default order — already puts the best match first.
    func search(_ query: String) throws -> [SearchHit] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT message.id, message.chatID, message.text, message.createdAt
                    FROM message_fts
                    JOIN message ON message.rowid = message_fts.rowid
                    WHERE message_fts MATCH ?
                    ORDER BY bm25(message_fts)
                    LIMIT 50
                    """,
                arguments: [Self.ftsQuery(for: query)]
            )
            .compactMap { row -> SearchHit? in
                guard let id = UUID(uuidString: row["id"]), let chatID = UUID(uuidString: row["chatID"]) else {
                    return nil
                }
                return SearchHit(id: id, chatID: chatID, text: row["text"], createdAt: row["createdAt"])
            }
        }
    }

    /// FTS5's MATCH syntax gives bare terms special meaning (`-`, `*`, column filters, and a
    /// leading digit can be parsed as a token modifier). Quoting each whitespace-split term as
    /// its own phrase is the documented way to search arbitrary user text without those terms
    /// being interpreted as query syntax.
    private static func ftsQuery(for raw: String) -> String {
        raw
            .split(separator: " ")
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " ")
    }
}
