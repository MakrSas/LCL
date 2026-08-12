import Foundation

/// Replays a scripted response, token by token, with realistic pacing.
///
/// This is the most valuable test infrastructure in the project (docs/PHASE_1_PLAN.md
/// Step 6). It lets the whole loop — streaming, cancellation, persistence, and later the
/// agent loop's permission gates and branch policy — be verified in CI on a simulator, with
/// no GPU and no 2.5 GB of weights. On a machine with no Mac that is the difference between
/// testable and not.
actor MockModelProvider: ModelProvider {
    // `nonisolated` on the synchronous requirements: `ModelProvider` exposes these without
    // `async` so a view can read capabilities during layout. They are immutable `let`s of
    // Sendable type, so reading them off the actor is safe.
    nonisolated let descriptor = ModelDescriptor(
        id: "mock",
        displayName: "Mock",
        developer: "LCL",
        parameterSummary: "scripted",
        quantization: "—",
        downloadBytes: 0
    )

    nonisolated let capabilities = ModelCapabilities(
        maxContextTokens: 32_768,
        supportsVision: false,
        supportsAudioInput: false,
        supportsThinking: true,
        toolCalling: .none,
        guidedGeneration: false,
        estimatedResidentBytes: 0
    )

    private var loaded = false
    nonisolated private let script: [String]
    nonisolated private let thinkingScript: String?
    nonisolated private let tokenDelay: Duration

    var isLoaded: Bool { loaded }

    // No `nonisolated` here: an actor's synchronous init is already nonisolated, and saying
    // so explicitly is an error.
    init(
        script: [String] = MockModelProvider.defaultScript,
        thinking: String? = "Considering how to answer this clearly.",
        tokenDelay: Duration = .milliseconds(18)
    ) {
        self.script = script
        self.thinkingScript = thinking
        self.tokenDelay = tokenDelay
    }

    func load(progress: @Sendable @escaping (Double) -> Void) async throws {
        for step in 1...10 {
            try await Task.sleep(for: .milliseconds(20))
            progress(Double(step) / 10)
        }
        loaded = true
    }

    func unload() async {
        loaded = false
    }

    func countTokens(_ text: String) async throws -> Int {
        // Deliberately crude — it is a mock. The real provider must use the real tokenizer;
        // chars/4 heuristics cause context overflow at the worst possible moment.
        max(1, text.count / 4)
    }

    nonisolated func stream(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let started = ContinuousClock.now
                var completionTokens = 0

                if let thinkingScript {
                    for chunk in Self.tokenize(thinkingScript) {
                        try Task.checkCancellation()
                        try await Task.sleep(for: tokenDelay)
                        continuation.yield(.thinking(chunk))
                    }
                }

                let response = Self.response(for: request.prompt, script: script)
                for chunk in Self.tokenize(response) {
                    try Task.checkCancellation()
                    try await Task.sleep(for: tokenDelay)
                    continuation.yield(.prose(chunk))
                    completionTokens += 1
                }

                let elapsed = started.duration(to: .now)
                let seconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1e18
                continuation.yield(.usage(TokenUsage(
                    promptTokens: max(1, request.prompt.count / 4),
                    completionTokens: completionTokens,
                    tokensPerSecond: seconds > 0 ? Double(completionTokens) / seconds : 0
                )))
                continuation.yield(.finished(.stop))
                continuation.finish()
            }

            continuation.onTermination = { reason in
                if case .cancelled = reason { task.cancel() }
            }
        }
    }

    // MARK: Scripting

    private static func response(for prompt: String, script: [String]) -> String {
        let hash = abs(prompt.hashValue)
        return script[hash % script.count]
    }

    /// Splits into word-ish chunks so streaming looks like real generation rather than a
    /// character crawl.
    private static func tokenize(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == " " || character == "\n" {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    static let defaultScript: [String] = [
        """
        LCL runs the model **on your iPhone**. Nothing leaves the device unless you turn on \
        web, GitHub or plugins.

        A few things worth knowing:

        - the context window is chosen from your device's RAM, not the model's maximum
        - history is never destroyed by compaction, only summarised into the active context
        - every tool call is validated and permission-checked by the app, not the model

        Ask me anything and I'll stream the answer as it's generated.
        """,
        """
        ## Streaming

        This response arrives block by block. Only the *trailing* block is re-parsed as \
        tokens land, so a long answer stays smooth instead of getting slower as it grows.

        ```swift
        for try await event in provider.stream(request) {
            switch event {
            case .prose(let delta): buffer += delta
            case .thinking(let delta): reasoning += delta
            case .usage(let usage): metrics = usage
            case .finished: break
            }
        }
        ```

        Deltas are coalesced on a display timer rather than delivered per token — per-token \
        SwiftUI invalidation is how these apps end up at 15fps.
        """,
        """
        The model may forget. LCL must not.

        1. everything you say is stored raw, forever
        2. compaction extracts typed facts, each citing its source event
        3. retrieval brings back what the current step needs

        > A small model with good context management beats a large one with none.
        """,
    ]
}
