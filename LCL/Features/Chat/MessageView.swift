import SwiftUI

struct MessageView: View {
    let message: ChatMessage
    let onCopy: () -> Void
    let onRegenerate: () -> Void

    @State private var showThinking = false
    @State private var copyTrigger = 0

    var body: some View {
        switch message.role {
        case .user:
            userMessage
        case .assistant:
            assistantMessage
        }
    }

    // MARK: User

    /// The only place in the transcript that gets a surface.
    private var userMessage: some View {
        HStack {
            Spacer(minLength: Space.section)
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, Space.base)
                .padding(.vertical, Space.tight + 2)
                .background(
                    Palette.surfaceUser,
                    in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You said: \(message.text)")
    }

    // MARK: Assistant

    /// Never wrapped in a bubble — assistant prose sits directly on the canvas
    /// (docs/DESIGN_SYSTEM.md §1). This is the most-read text in the app.
    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            if message.hasThinking {
                thinkingSection
            }

            MarkdownView(blocks: message.blocks)

            if message.isStreaming {
                if message.text.isEmpty && !message.hasThinking {
                    TypingIndicator()
                }
            } else if !message.text.isEmpty {
                actionRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// Collapsed and quiet. Reasoning is never the visual focus.
    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Button {
                showThinking.toggle()
            } label: {
                HStack(spacing: Space.hair) {
                    Image(systemName: showThinking ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("Thinking")
                        .font(.subheadline)
                }
                .foregroundStyle(Palette.thinking)
            }
            .buttonStyle(.plain)
            .haptic(.reasoningDetent, trigger: showThinking)
            .accessibilityLabel(showThinking ? "Hide reasoning" : "Show reasoning")

            if showThinking {
                Text(message.thinking)
                    .font(.subheadline)
                    .foregroundStyle(Palette.thinking)
                    .textSelection(.enabled)
                    .padding(.leading, Space.base)
            }
        }
        .lclAnimation(MotionSystem.standard, value: showThinking)
    }

    /// Appears only once a message has settled — not during streaming, where it would
    /// flicker and invite mis-taps.
    private var actionRow: some View {
        HStack(spacing: Space.base) {
            Button {
                onCopy()
                copyTrigger += 1
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .accessibilityLabel("Copy")

            Button {
                onRegenerate()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Regenerate")

            ShareLink(item: message.text) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share")
        }
        .font(.subheadline)
        .buttonStyle(.quiet)
        .padding(.top, Space.hair)
        .haptic(.selection, trigger: copyTrigger)
    }
}

/// Shown only in the gap between sending and the first token, so the app never looks frozen.
struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    var body: some View {
        HStack(spacing: Space.hair + 1) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Palette.textTertiary)
                    .frame(width: 6, height: 6)
                    .opacity(reduceMotion ? 0.6 : (phase == index ? 1 : 0.35))
            }
        }
        .accessibilityLabel("Generating a response")
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                phase = (phase + 1) % 3
            }
        }
    }
}
