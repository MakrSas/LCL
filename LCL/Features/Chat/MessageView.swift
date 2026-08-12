import SwiftUI

struct MessageView: View {
    let message: ChatMessage
    let onCopy: () -> Void
    let onRegenerate: () -> Void

    @State private var showThinking = false
    @State private var copyTrigger = 0
    @State private var copied = false

    var body: some View {
        Group {
            switch message.role {
            case .user:
                userMessage
            case .assistant:
                assistantMessage
            }
        }
        .appearOnce()
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
                    // Rotation rather than a glyph swap: the chevron is the same object
                    // turning, which is what the system does everywhere else.
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(showThinking ? 90 : 0))
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
                    // Grows from the top edge rather than fading in place, so the reveal
                    // reads as the panel opening.
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
        .lclAnimation(MotionSystem.standard, value: showThinking)
    }

    /// Appears only once a message has settled — not during streaming, where it would
    /// flicker and invite mis-taps.
    private var actionRow: some View {
        HStack(spacing: Space.base) {
            Button {
                onCopy()
                copied = true
                copyTrigger += 1
                // Confirmation is transient: the checkmark says "done" and then gets out of
                // the way, rather than leaving the row in a changed state.
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    // The glyph morphs instead of snapping — the system's own idiom for a
                    // symbol changing meaning in place.
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(copied ? "Copied" : "Copy")

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
        .appearOnce()
    }
}

/// Shown only in the gap between sending and the first token, so the app never looks frozen.
///
/// A system symbol effect rather than three hand-animated circles: it is one line, it matches
/// the platform's own waiting idiom, and it honours Reduce Motion without us handling that.
struct TypingIndicator: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.title3)
            .foregroundStyle(Palette.textTertiary)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers)
            .accessibilityLabel("Generating a response")
    }
}
