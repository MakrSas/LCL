import SwiftUI

struct ChatView: View {
    /// Plain `let`: `@Observable` tracks the reads in `body` automatically, and no binding
    /// into the view model is needed here.
    let viewModel: ChatViewModel
    let onOpenSidebar: () -> Void

    @State private var draft = ""
    @State private var thinkingEnabled = true
    @State private var isNearBottom = true

    var body: some View {
        ScrollViewReader { scroller in
            transcript
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // safeAreaInset rather than an overlay: this way the transcript's own
                    // insets stay correct, so content can scroll clear of the composer and
                    // the keyboard instead of hiding behind it.
                    Composer(
                        text: $draft,
                        isStreaming: viewModel.isStreaming,
                        supportsThinking: viewModel.capabilities.supportsThinking,
                        thinkingEnabled: $thinkingEnabled,
                        onSend: send,
                        onStop: viewModel.stop
                    )
                    .padding(.horizontal, Layout.gutter)
                    .padding(.bottom, Space.tight)
                }
                // ignoresSafeArea: a plain background stops at the safe area, which left a
                // lighter band under the status bar and above the home indicator.
                .background(Palette.canvas.ignoresSafeArea())
                .toolbar { toolbarContent }
                // Both are needed. Hiding the background alone still left a hairline under
                // the bar — that divider is the scroll edge effect, not the material.
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .onChange(of: viewModel.messages.last?.blocks.count) { _, _ in
                    // Only follow the stream if the user is already at the bottom. Yanking
                    // someone back down while they are reading is the most common chat-UI
                    // sin (docs/PRODUCT_SPEC.md §4).
                    guard isNearBottom, let lastID = viewModel.messages.last?.id else { return }
                    withAnimation(MotionSystem.gentle) {
                        scroller.scrollTo(lastID, anchor: .bottom)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isNearBottom && !viewModel.messages.isEmpty {
                        scrollToBottomButton(scroller)
                    }
                }
                .lclAnimation(MotionSystem.standard, value: isNearBottom)
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.loose) {
                // Nothing at all when empty. The wordmark was decoration, and giving it the
                // container's height made an empty chat scrollable, which it must not be.
                // A useful empty state arrives with persistence (Step 2), when there is real
                // recent history to list.
                ForEach(viewModel.messages) { message in
                    MessageView(
                        message: message,
                        onCopy: { UIPasteboard.general.string = message.text },
                        onRegenerate: viewModel.regenerate
                    )
                    .id(message.id)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(Palette.destructive)
                }
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, Space.base)
            .padding(.bottom, Space.base)
        }
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let distanceFromBottom = geometry.contentSize.height
                - (geometry.contentOffset.y + geometry.containerSize.height)
            return distanceFromBottom < 90
        } action: { _, nearBottom in
            isNearBottom = nearBottom
        }
    }

    private func scrollToBottomButton(_ scroller: ScrollViewProxy) -> some View {
        Button {
            guard let lastID = viewModel.messages.last?.id else { return }
            withAnimation(MotionSystem.gentle) {
                scroller.scrollTo(lastID, anchor: .bottom)
            }
        } label: {
            Image(systemName: "arrow.down")
        }
        // System glass, not a glass background behind a plain button.
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .padding(.trailing, Layout.gutter)
        .padding(.bottom, Space.tight)
        // Scales up from the corner it will act on, so the control's origin is legible.
        .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
        .accessibilityLabel("Scroll to latest")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // No button style here. Toolbar items already get the system glass treatment on
            // this OS; adding `.glass` on top produced a circle inside a circle.
            Button(action: onOpenSidebar) {
                Image(systemName: "sidebar.left")
            }
            .accessibilityLabel("Open sidebar")
        }
        ToolbarItem(placement: .principal) {
            Text("LCL")
                .font(.headline)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        viewModel.send(text)
    }
}
