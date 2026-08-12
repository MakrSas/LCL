import Foundation

// The abstraction from docs/ARCHITECTURE.md §4, sized to what it must actually carry.
//
// Everything model-shaped lives behind this: prompt format, tool-call grammar, thinking
// delimiters, memory lifecycle. None of it is visible to a view.

// MARK: - Capabilities

enum ToolCallingSupport: String, Sendable, Codable {
    case none
    case promptBased
    case native
}

/// Drives the UI directly. The Composer's Thinking control and the attachment menu's camera
/// entry read from here, so swapping in a model without vision removes the camera button
/// with no per-feature code. That is the only reason this abstraction exists.
struct ModelCapabilities: Sendable, Equatable {
    var maxContextTokens: Int
    var supportsVision: Bool
    var supportsAudioInput: Bool
    var supportsThinking: Bool
    var toolCalling: ToolCallingSupport
    var guidedGeneration: Bool
    var estimatedResidentBytes: Int

    /// Gemma 4 E2B as LCL will actually run it. Note what is *false*: Swift-side vision and
    /// audio are unconfirmed, and MLXGuidedGeneration is not in a tagged release
    /// (docs/RESEARCH_LOG.md §3). Claiming a capability we cannot deliver is the failure
    /// docs/PRODUCT_SPEC.md forbids.
    static let gemma4E2B = ModelCapabilities(
        maxContextTokens: 32_768,
        supportsVision: false,
        supportsAudioInput: false,
        supportsThinking: true,
        toolCalling: .native,
        guidedGeneration: false,
        estimatedResidentBytes: 3_100_000_000
    )
}

struct ModelDescriptor: Sendable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var developer: String
    var parameterSummary: String
    var quantization: String
    var downloadBytes: Int

    static let gemma4E2B = ModelDescriptor(
        id: "mlx-community/gemma-4-e2b-it-4bit",
        displayName: "Gemma 4 E2B",
        developer: "Google",
        parameterSummary: "2.3B effective",
        quantization: "4-bit",
        downloadBytes: 2_500_000_000
    )
}

// MARK: - Generation

struct GenerationRequest: Sendable {
    var prompt: String
    var history: [GenerationTurn]
    var maxTokens: Int
    var temperature: Double

    init(prompt: String, history: [GenerationTurn] = [], maxTokens: Int = 1024, temperature: Double = 0.7) {
        self.prompt = prompt
        self.history = history
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

struct GenerationTurn: Sendable, Equatable {
    enum Role: String, Sendable { case user, assistant }
    var role: Role
    var text: String
}

struct TokenUsage: Sendable, Equatable {
    var promptTokens: Int
    var completionTokens: Int
    var tokensPerSecond: Double
}

enum FinishReason: String, Sendable {
    case stop
    case maxTokens
    case cancelled
    case error
}

/// Thinking and prose are separate cases so the UI can collapse reasoning without doing
/// string surgery on a single stream.
enum GenerationEvent: Sendable {
    case prose(String)
    case thinking(String)
    case usage(TokenUsage)
    case finished(FinishReason)
}

// MARK: - Provider

protocol ModelProvider: Sendable {
    var descriptor: ModelDescriptor { get }
    var capabilities: ModelCapabilities { get }

    var isLoaded: Bool { get async }

    func load(progress: @Sendable @escaping (Double) -> Void) async throws
    func unload() async

    func stream(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, Error>
    func countTokens(_ text: String) async throws -> Int
}

enum ModelProviderError: LocalizedError {
    case notLoaded
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "The model isn't loaded yet."
        case .unsupported(let detail):
            return detail
        }
    }
}
