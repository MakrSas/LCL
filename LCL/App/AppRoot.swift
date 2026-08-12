import SwiftUI

/// Chat is the root, with everything else reached from it. Not a tab bar: a tab bar would
/// imply several co-equal destinations, and they are not co-equal (docs/PRODUCT_SPEC.md §1).
struct AppRoot: View {
    /// Phase 1 runs on the mock provider. Gemma4Provider arrives in Step 7 and drops in
    /// behind the same `ModelProvider` protocol without any view changing.
    @State private var viewModel = ChatViewModel(provider: MockModelProvider())
    @State private var isSidebarOpen = false

    var body: some View {
        SidebarContainer(isOpen: $isSidebarOpen) {
            SidebarView(
                recentTitles: recentTitles,
                onNewChat: {
                    viewModel.clear()
                    setSidebar(open: false)
                },
                onClose: { setSidebar(open: false) }
            )
        } content: {
            NavigationStack {
                ChatView(viewModel: viewModel) {
                    setSidebar(open: true)
                }
            }
        }
        .background(Palette.canvas)
        .preferredColorScheme(nil)
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
