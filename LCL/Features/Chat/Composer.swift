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
            // Generous vertical rhythm: the composer is the thing you touch most, and a
            // minimum-height box with the controls crowding the text reads as cramped next to
            // the system's own input surfaces.
            VStack(alignment: .leading, spacing: Space.base) {
                // Grows with content, then scrolls internally rather than eating the screen.
                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.body)
                    .focused($isFocused)
                    .submitLabel(.return)
                    .padding(.horizontal, Space.hair)
                    .frame(minHeight: 26)

                // Every control here is a system button style. No hand-built capsules or
                // circles: only `.glass` / `.glassProminent` stretch under the finger and
                // throw a highlight, and a painted background cannot imitate that.
                HStack(spacing: Space.tight) {
                    // Options live behind `+` rather than as pills along the composer.
                    //
                    // A plain `Menu` with a `Toggle` inside: the system draws the checkmark,
                    // the material and the presentation, and reports the right accessibility
                    // traits. Camera, Photos, Files and Plugins join this menu when those
                    // features exist — today it holds the one option that is real.
                    Menu {
                        if supportsThinking {
                            Toggle(isOn: $thinkingEnabled) {
                                Label("Thinking", systemImage: "sparkles")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .haptic(.menuOpened, trigger: thinkingEnabled)
                    .accessibilityLabel("Options")

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
                // Default control size. `.large` made these overpower the composer — the text
                // field is the primary element here, not the buttons around it.
            }
            .padding(.horizontal, Space.base)
            .padding(.vertical, Space.base)
        }
        .lclAnimation(MotionSystem.standard, value: isStreaming)
        .lclAnimation(MotionSystem.standard, value: canSend)
        .lclAnimation(MotionSystem.standard, value: thinkingEnabled)
        // Height only actually changes at line boundaries, so keying on the text animates
        // the growth without animating every keystroke.
        .lclAnimation(MotionSystem.standard, value: text)
    }
}
