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
                .background(Palette.canvas)
                .toolbar { toolbarContent }
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
                if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.messages) { message in
                        MessageView(
                            message: message,
                            onCopy: { UIPasteboard.general.string = message.text },
                            onRegenerate: viewModel.regenerate
                        )
                        .id(message.id)
                    }
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

    /// Wordmark and one line. No suggested-prompt grid — that is what makes an app feel like
    /// a demo.
    private var emptyState: some View {
        VStack(spacing: Space.tight) {
            Text("LCL")
                .font(.largeTitle.weight(.semibold))
            Text("Your AI, running on your iPhone.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
        .accessibilityElement(children: .combine)
    }

    private func scrollToBottomButton(_ scroller: ScrollViewProxy) -> some View {
        Button {
            guard let lastID = viewModel.messages.last?.id else { return }
            withAnimation(MotionSystem.gentle) {
                scroller.scrollTo(lastID, anchor: .bottom)
            }
        } label: {
            Image(systemName: "arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .background {
            GlassCluster(cornerRadius: 18, spacing: nil, interactive: true) {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.trailing, Layout.gutter)
        .padding(.bottom, Space.tight)
        // Scales up from the corner it will act on, so the control's origin is legible.
        .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
        .accessibilityLabel("Scroll to latest")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
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
