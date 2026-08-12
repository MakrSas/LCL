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

                HStack(spacing: Space.tight) {
                    if supportsThinking {
                        Button {
                            thinkingEnabled.toggle()
                        } label: {
                            Text("Thinking")
                                .font(.subheadline)
                                .padding(.horizontal, Space.tight + 2)
                                .frame(height: 32)
                                .background(
                                    thinkingEnabled ? Color.accentColor.opacity(0.16) : Color.clear,
                                    in: Capsule()
                                )
                                .foregroundStyle(thinkingEnabled ? Color.accentColor : Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .haptic(.toggle, trigger: thinkingEnabled)
                        .accessibilityLabel("Thinking")
                        .accessibilityValue(thinkingEnabled ? "On" : "Off")
                    }

                    Spacer(minLength: 0)

                    // Same position and size in both states: the control must not move
                    // under the user's thumb when generation starts.
                    Button {
                        if isStreaming {
                            onStop()
                        } else if canSend {
                            sendTrigger += 1
                            onSend()
                        }
                    } label: {
                        Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(sendForeground)
                            // The arrow morphs into the stop square in place, rather than
                            // one glyph snapping out and another in.
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 34, height: 34)
                            .background(sendBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isStreaming && !canSend)
                    .minimumHitTarget()
                    .haptic(.messageSent, trigger: sendTrigger)
                    .accessibilityLabel(isStreaming ? "Stop generating" : "Send message")
                }
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

    private var sendBackground: Color {
        if isStreaming { return Palette.surfaceUser }
        return canSend ? Color.accentColor : Palette.surfaceUser
    }

    private var sendForeground: Color {
        if isStreaming { return Palette.textPrimary }
        return canSend ? .white : Palette.textTertiary
    }
}
