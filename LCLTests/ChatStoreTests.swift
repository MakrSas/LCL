import XCTest
@testable import LCL

/// Covers docs/PHASE_1_PLAN.md Step 2's "Done" line: round-trip tests, FTS search returns
/// ranked results, migration from empty runs clean. The third is implicit — every test here
/// runs the real migrator from empty, in memory, before touching anything else.
final class ChatStoreTests: XCTestCase {

    private func makeStore() throws -> ChatStore {
        ChatStore(dbQueue: try AppDatabase.openInMemory())
    }

    func testCreateChatAppearsInListing() async throws {
        let store = try makeStore()
        let chatID = try await store.createChat(title: "First chat")

        let chats = try await store.listChats()

        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(chats.first?.id, chatID)
        XCTAssertEqual(chats.first?.title, "First chat")
    }

    func testNewestChatSortsFirst() async throws {
        let store = try makeStore()
        let older = try await store.createChat(title: "Older")
        // `createChat` timestamps with `Date()`; without a real gap the two rows can tie at
        // whatever precision the column actually stores, and `ORDER BY updatedAt DESC` gives
        // no guarantee about tie order.
        try await Task.sleep(for: .seconds(1))
        let newer = try await store.createChat(title: "Newer")

        let chats = try await store.listChats()

        XCTAssertEqual(chats.map(\.id), [newer, older])
    }

    func testMessageRoundTripsThroughLoad() async throws {
        let store = try makeStore()
        let chatID = try await store.createChat()
        let message = ChatMessage(role: .user, text: "hello there")

        try await store.insertMessage(message, chatID: chatID)
        let loaded = try await store.loadMessages(chatID: chatID)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, message.id)
        XCTAssertEqual(loaded.first?.text, "hello there")
        XCTAssertEqual(loaded.first?.role, .user)
    }

    func testMessagesLoadInCreationOrder() async throws {
        let store = try makeStore()
        let chatID = try await store.createChat()
        let first = ChatMessage(role: .user, text: "first", createdAt: Date(timeIntervalSince1970: 1))
        let second = ChatMessage(role: .assistant, text: "second", createdAt: Date(timeIntervalSince1970: 2))

        // Inserted out of order to actually exercise the ORDER BY rather than getting lucky
        // with insertion order matching query order.
        try await store.insertMessage(second, chatID: chatID)
        try await store.insertMessage(first, chatID: chatID)

        let loaded = try await store.loadMessages(chatID: chatID)

        XCTAssertEqual(loaded.map(\.text), ["first", "second"])
    }

    /// Reproduces `ChatViewModel`'s real sequence: an empty, `isStreaming: true` placeholder
    /// inserted at `send()`, finished later with the accumulated text — never with the buffer
    /// pushed through on every `flush()` tick.
    func testFinishMessageUpdatesPlaceholderWithoutDuplicating() async throws {
        let store = try makeStore()
        let chatID = try await store.createChat()
        let placeholder = ChatMessage(role: .assistant, isStreaming: true)
        try await store.insertMessage(placeholder, chatID: chatID)

        try await store.finishMessage(
            placeholder.id,
            text: "the full reply",
            thinking: "reasoning trace",
            usage: TokenUsage(promptTokens: 10, completionTokens: 20, tokensPerSecond: 42)
        )

        let loaded = try await store.loadMessages(chatID: chatID)

        XCTAssertEqual(loaded.count, 1, "finishing must update the existing row, not insert a second one")
        XCTAssertEqual(loaded.first?.text, "the full reply")
        XCTAssertEqual(loaded.first?.thinking, "reasoning trace")
        XCTAssertEqual(loaded.first?.isStreaming, false)
    }

    func testInsertingMessageTouchesChatUpdatedAt() async throws {
        let store = try makeStore()
        let chatID = try await store.createChat()
        let before = try await store.listChats().first!.updatedAt

        // A real time gap, not just a subsequent line of code, so this can't pass by
        // accident regardless of the column's actual stored precision.
        try await Task.sleep(for: .seconds(1))
        try await store.insertMessage(ChatMessage(role: .user, text: "hi"), chatID: chatID)

        let after = try await store.listChats().first!.updatedAt
        XCTAssertGreaterThan(after, before)
    }

    func testDeletingChatCascadesToMessages() async throws {
        let store = try makeStore()
        let chatID = try await store.createChat()
        try await store.insertMessage(ChatMessage(role: .user, text: "will be deleted"), chatID: chatID)

        try await store.deleteChat(chatID)

        let chats = try await store.listChats()
        let messages = try await store.loadMessages(chatID: chatID)
        XCTAssertTrue(chats.isEmpty)
        XCTAssertTrue(messages.isEmpty)
    }

    // MARK: - Search

    func testSearchFindsMatchingMessageAcrossChats() async throws {
        let store = try makeStore()
        let chatA = try await store.createChat(title: "A")
        let chatB = try await store.createChat(title: "B")
        try await store.insertMessage(ChatMessage(role: .user, text: "how do I bake sourdough bread"), chatID: chatA)
        try await store.insertMessage(ChatMessage(role: .assistant, text: "totally unrelated reply"), chatID: chatB)

        let hits = try await store.search("sourdough")

        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.chatID, chatA)
    }

    /// The actual reason FTS5/BM25 was chosen over a `LIKE` scan (docs/ARCHITECTURE.md): the
    /// query term that appears in fewer, shorter messages should rank first.
    func testSearchRanksMoreRelevantMessageFirst() async throws {
        let store = try makeStore()
        let chatID = try await store.createChat()
        try await store.insertMessage(
            ChatMessage(role: .user, text: "swift concurrency swift concurrency swift concurrency actors"),
            chatID: chatID
        )
        try await store.insertMessage(
            ChatMessage(role: .user, text: "swift"),
            chatID: chatID
        )

        let hits = try await store.search("swift")

        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits.first?.text, "swift", "the short, term-dense message should rank above the long dilute one")
    }

    func testSearchWithBlankQueryReturnsNoResultsRatherThanEverything() async throws {
        let store = try makeStore()
        let chatID = try await store.createChat()
        try await store.insertMessage(ChatMessage(role: .user, text: "anything"), chatID: chatID)

        let hits = try await store.search("   ")

        XCTAssertTrue(hits.isEmpty)
    }

    /// FTS5 MATCH gives bare `-`, `*`, and `:` special meaning. A query built from ordinary
    /// user text containing them must not throw a syntax error back at the caller — the `try`
    /// below is the assertion: an unhandled FTS5 syntax error fails this test on its own.
    func testSearchToleratesFTS5SyntaxCharactersInUserInput() async throws {
        let store = try makeStore()
        let chatID = try await store.createChat()
        try await store.insertMessage(ChatMessage(role: .user, text: "check out my-repo:main *docs*"), chatID: chatID)

        _ = try await store.search("my-repo:main *docs*")
    }
}
