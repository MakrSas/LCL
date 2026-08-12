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
            // One row that grows, rather than two layouts swapped on focus. Swapping would
            // recreate the TextField at the exact moment it gains focus — losing that focus and
            // collapsing it straight back. This is compact when idle and taller as you type,
            // with the controls staying at the bottom.
            HStack(alignment: .bottom, spacing: Space.tight) {
                // Options live behind `+` rather than as pills along the composer.
                //
                // A plain `Menu` with a `Toggle` inside: the system draws the checkmark, the
                // material and the presentation, and reports the right accessibility traits.
                // Camera, Photos, Files and Plugins join this menu when those features exist —
                // today it holds the one option that is real.
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

                // Grows with content, then scrolls internally rather than eating the screen.
                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.body)
                    .focused($isFocused)
                    .submitLabel(.return)
                    .padding(.vertical, Space.tight)

                // Same position and size in both states: the control must not move under the
                // user's thumb when generation starts.
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
            .padding(.horizontal, Space.tight + 2)
            .padding(.vertical, Space.tight)
        }
        .lclAnimation(MotionSystem.standard, value: isStreaming)
        .lclAnimation(MotionSystem.standard, value: canSend)
        .lclAnimation(MotionSystem.standard, value: thinkingEnabled)
        // Height only actually changes at line boundaries, so keying on the text animates
        // the growth without animating every keystroke.
        .lclAnimation(MotionSystem.standard, value: text)
    }
}
