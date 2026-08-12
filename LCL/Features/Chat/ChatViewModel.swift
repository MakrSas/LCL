import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isStreaming = false
    private(set) var lastUsage: TokenUsage?
    private(set) var errorMessage: String?

    /// Bumped when a message is sent, so a haptic can be attached without the view watching
    /// the whole message array.
    private(set) var sendCount = 0

    private let provider: any ModelProvider
    private var streamTask: Task<Void, Never>?

    /// Deltas land here and are flushed to the message on a display timer. Per-token
    /// SwiftUI invalidation is the standard way these apps end up at 15fps
    /// (docs/ARCHITECTURE.md §11).
    private var proseBuffer = ""
    private var thinkingBuffer = ""

    /// `nonisolated` so a `@State` property initialiser can construct it without hopping to
    /// the main actor. It only assigns stored properties, so this is safe.
    nonisolated init(provider: any ModelProvider) {
        self.provider = provider
    }

    var capabilities: ModelCapabilities { provider.capabilities }

    var canSend: Bool { !isStreaming }

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: text))
        sendCount += 1

        let assistant = ChatMessage(role: .assistant, isStreaming: true)
        messages.append(assistant)
        isStreaming = true

        let history = messages.dropLast(2).map {
            GenerationTurn(role: $0.role == .user ? .user : .assistant, text: $0.text)
        }
        let request = GenerationRequest(prompt: text, history: Array(history))

        streamTask = Task { [weak self] in
            await self?.consume(request: request, messageID: assistant.id)
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        flush()
        finishStreaming()
    }

    func regenerate() {
        guard !isStreaming,
              let lastUser = messages.last(where: { $0.role == .user })?.text
        else { return }
        // Drop the previous assistant turn so the new one replaces it rather than stacking.
        if messages.last?.role == .assistant { messages.removeLast() }
        if messages.last?.role == .user { messages.removeLast() }
        send(lastUser)
    }

    func clear() {
        stop()
        messages.removeAll()
        lastUsage = nil
        errorMessage = nil
    }

    // MARK: - Streaming

    private func consume(request: GenerationRequest, messageID: UUID) async {
        let flusher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                self?.flush(into: messageID)
            }
        }

        do {
            for try await event in provider.stream(request) {
                switch event {
                case .prose(let delta):
                    proseBuffer += delta
                case .thinking(let delta):
                    thinkingBuffer += delta
                case .usage(let usage):
                    lastUsage = usage
                case .finished:
                    break
                }
            }
        } catch is CancellationError {
            // Stopping is a normal outcome, not an error worth surfacing.
        } catch {
            errorMessage = error.localizedDescription
        }

        flusher.cancel()
        flush(into: messageID)
        finishStreaming()
    }

    private func flush(into messageID: UUID? = nil) {
        guard !proseBuffer.isEmpty || !thinkingBuffer.isEmpty else { return }
        let targetID = messageID ?? messages.last?.id
        guard let index = messages.lastIndex(where: { $0.id == targetID }) else { return }

        if !proseBuffer.isEmpty {
            messages[index].append(proseBuffer)
            proseBuffer = ""
        }
        if !thinkingBuffer.isEmpty {
            messages[index].thinking += thinkingBuffer
            thinkingBuffer = ""
        }
    }

    private func finishStreaming() {
        if let index = messages.indices.last {
            messages[index].isStreaming = false
        }
        isStreaming = false
        streamTask = nil
    }
}
