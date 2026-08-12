import SwiftUI

/// The floating composer.
///
/// Phase 1 shows only controls that do something: the text field, a Thinking toggle when the
/// loaded model supports it, and send/stop. No attachment button (Files is Phase 2) and no
/// mic or voice (Phase 7) — docs/PRODUCT_SPEC.md forbids controls that hint at features which
/// do not exist yet.
struct Composer: View {
    @Binding var text: String
    let isStreaming: Bool
    let supportsThinking: Bool
    @Binding var thinkingEnabled: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool
    @State private var sendTrigger = 0

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassCluster(cornerRadius: Radius.sheet) {
            VStack(spacing: Space.tight) {
                // Grows with content, then scrolls internally rather than eating the screen.
                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.body)
                    .focused($isFocused)
                    .submitLabel(.return)
                    .padding(.horizontal, Space.hair)

                // Every control here is a system button style. No hand-built capsules or
                // circles: only `.glass` / `.glassProminent` stretch under the finger and
                // throw a highlight, and a painted background cannot imitate that.
                HStack(spacing: Space.tight) {
                    if supportsThinking {
                        // A Toggle, not a Button: this is a binary state, and
                        // `.toggleStyle(.button)` is the platform's own way to express one as
                        // a control. It renders the on/off state and reports the right
                        // accessibility traits without us styling either.
                        Toggle("Thinking", isOn: $thinkingEnabled)
                            .toggleStyle(.button)
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .haptic(.toggle, trigger: thinkingEnabled)
                    }

                    Spacer(minLength: 0)

                    // Same position and size in both states: the control must not move under
                    // the user's thumb when generation starts.
                    Button {
                        if isStreaming {
                            onStop()
                        } else if canSend {
                            sendTrigger += 1
                            onSend()
                        }
                    } label: {
                        Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                            // The arrow morphs into the stop square in place.
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .disabled(!isStreaming && !canSend)
                    .haptic(.messageSent, trigger: sendTrigger)
                    .accessibilityLabel(isStreaming ? "Stop generating" : "Send message")
                }
                .controlSize(.large)
            }
            .padding(.horizontal, Space.base - Space.hair)
            .padding(.vertical, Space.tight + 2)
        }
        .lclAnimation(MotionSystem.standard, value: isStreaming)
        .lclAnimation(MotionSystem.standard, value: canSend)
        .lclAnimation(MotionSystem.standard, value: thinkingEnabled)
        // Height only actually changes at line boundaries, so keying on the text animates
        // the growth without animating every keystroke.
        .lclAnimation(MotionSystem.standard, value: text)
    }
}
