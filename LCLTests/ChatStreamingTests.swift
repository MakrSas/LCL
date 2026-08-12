import XCTest
@testable import LCL

/// Exercises the streaming loop end to end against `MockModelProvider`.
///
/// This is the pattern the whole project depends on: no GPU, no weights, no device — so the
/// loop stays verifiable in CI from a Windows machine (docs/PHASE_1_PLAN.md Step 6). The
/// agent loop's permission gates and branch policy will be tested the same way.
@MainActor
final class ChatStreamingTests: XCTestCase {

    private func makeViewModel(delay: Duration = .milliseconds(1)) -> ChatViewModel {
        ChatViewModel(provider: MockModelProvider(tokenDelay: delay))
    }

    func testSendProducesUserAndAssistantMessages() async throws {
        let viewModel = makeViewModel()
        viewModel.send("Hello")

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertEqual(viewModel.messages[0].text, "Hello")
        XCTAssertEqual(viewModel.messages[1].role, .assistant)
        XCTAssertTrue(viewModel.isStreaming)

        try await waitUntil { !viewModel.isStreaming }

        XCTAssertFalse(viewModel.messages[1].text.isEmpty, "Assistant produced no text")
        XCTAssertFalse(viewModel.messages[1].isStreaming)
        XCTAssertFalse(viewModel.messages[1].blocks.isEmpty, "Markdown blocks were not built")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUsageIsReported() async throws {
        let viewModel = makeViewModel()
        viewModel.send("Tell me about streaming")
        try await waitUntil { !viewModel.isStreaming }

        let usage = try XCTUnwrap(viewModel.lastUsage)
        XCTAssertGreaterThan(usage.completionTokens, 0)
    }

    func testEmptyInputIsIgnored() {
        let viewModel = makeViewModel()
        viewModel.send("   \n  ")
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.isStreaming)
    }

    /// Stopping is a normal outcome and must not surface as an error to the user.
    func testStopEndsStreamingWithoutError() async throws {
        let viewModel = makeViewModel(delay: .milliseconds(30))
        viewModel.send("Hello")
        try await Task.sleep(for: .milliseconds(80))
        viewModel.stop()

        try await waitUntil { !viewModel.isStreaming }
        XCTAssertNil(viewModel.errorMessage, "Cancelling reported an error")
        XCTAssertFalse(viewModel.messages.last?.isStreaming ?? true)
    }

    func testCannotSendWhileStreaming() async throws {
        let viewModel = makeViewModel(delay: .milliseconds(20))
        viewModel.send("First")
        viewModel.send("Second")
        XCTAssertEqual(viewModel.messages.count, 2, "A second send was accepted mid-stream")
        try await waitUntil { !viewModel.isStreaming }
    }

    /// Regenerate must replace the previous answer rather than stacking a second one.
    func testRegenerateReplacesLastAnswer() async throws {
        let viewModel = makeViewModel()
        viewModel.send("Hello")
        try await waitUntil { !viewModel.isStreaming }
        XCTAssertEqual(viewModel.messages.count, 2)

        viewModel.regenerate()
        try await waitUntil { !viewModel.isStreaming }
        XCTAssertEqual(viewModel.messages.count, 2, "Regenerate stacked messages")
        XCTAssertEqual(viewModel.messages[0].text, "Hello")
    }

    func testClearRemovesEverything() async throws {
        let viewModel = makeViewModel()
        viewModel.send("Hello")
        try await waitUntil { !viewModel.isStreaming }
        viewModel.clear()
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertNil(viewModel.lastUsage)
    }

    func testCapabilitiesDriveUI() {
        let viewModel = makeViewModel()
        // The Composer's Thinking control is gated on this, so a model without thinking
        // support must remove the button rather than showing a dead one.
        XCTAssertTrue(viewModel.capabilities.supportsThinking)
        XCTAssertFalse(viewModel.capabilities.supportsVision)
    }

    // MARK: Helpers

    private func waitUntil(
        timeout: Duration = .seconds(10),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition")
    }
}
