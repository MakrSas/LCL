import SwiftUI

/// Chat is the root, with everything else reached from it. Not a tab bar: a tab bar would
/// imply several co-equal destinations, and they are not co-equal (docs/PRODUCT_SPEC.md §1).
struct AppRoot: View {
    /// Phase 1 runs on the mock provider. Gemma4Provider arrives in Step 7 and drops in
    /// behind the same `ModelProvider` protocol without any view changing.
    @State private var viewModel = ChatViewModel(provider: MockModelProvider())
    @State private var settings = AppSettings()
    @State private var isSidebarOpen = false
    @State private var showSettings = false

    var body: some View {
        // This reader does NOT ignore the safe area — that's the point. `SidebarContainer`
        // has its own inner GeometryReader with `.ignoresSafeArea()` applied (needed so the
        // drawer's offset/clip math operates on the true full-bleed screen, not a
        // safe-area-shrunk one), but reading `proxy.safeAreaInsets` from that SAME
        // already-ignoring reader turned out to rest on a genuinely disputed SwiftUI
        // behaviour: two directly-fetched sources gave opposite answers for whether such a
        // reader's proxy still reports non-zero insets or reports zero. Rather than trust
        // either, the true insets are captured once, here, from an ordinary reader that was
        // never told to ignore anything — the uncontested case both sources agree on — and
        // handed down as plain constants that `SidebarContainer` only consumes, never
        // re-derives.
        GeometryReader { rootProxy in
            SidebarContainer(
                isOpen: $isSidebarOpen,
                topInset: rootProxy.safeAreaInsets.top,
                bottomInset: rootProxy.safeAreaInsets.bottom
            ) {
                SidebarView(
                    recentTitles: recentTitles,
                    onNewChat: {
                        viewModel.clear()
                        setSidebar(open: false)
                    },
                    onOpenSettings: { showSettings = true },
                    onClose: { setSidebar(open: false) }
                )
            } content: {
                // No NavigationStack: Phase 1 has no push destinations, and its system
                // toolbar proved unreliable inside the sidebar's offset/clip/mask machinery
                // (see ChatView.topBar). Add it back once a real destination exists to push
                // to.
                ChatView(viewModel: viewModel) {
                    setSidebar(open: true)
                }
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        // One tint at the root propagates the chosen accent to every control, so components
        // read `Color.accentColor` rather than each one reaching for a palette constant.
        .tint(settings.accent.color)
        .environment(settings)
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environment(settings)
        }
    }

    /// Derived from the transcript for now. Real chat history lands with persistence
    /// (Step 2), and until then this shows only what actually exists rather than
    /// placeholder titles.
    private var recentTitles: [String] {
        guard let first = viewModel.messages.first(where: { $0.role == .user })?.text else {
            return []
        }
        return [String(first.prefix(40))]
    }

    private func setSidebar(open: Bool) {
        withAnimation(MotionSystem.sidebar) {
            isSidebarOpen = open
        }
    }
}
