import SwiftUI

/// Phase 1 shows only rows that lead somewhere. Projects, Plugins, Activity, Scheduled,
/// GitHub and Images arrive with their phases — an empty screen behind a row is worse than
/// no row (docs/PRODUCT_SPEC.md §2).
struct SidebarView: View {
    let recentTitles: [String]
    let onNewChat: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Space.loose) {
                    // Library, Projects, Plugins, Activity, Scheduled, GitHub and Images all
                    // arrive with their phases. A row leading to an empty screen is worse
                    // than no row.
                    if !recentTitles.isEmpty {
                        section("Recent") {
                            ForEach(recentTitles, id: \.self) { title in
                                row(title, systemImage: "bubble.left")
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.base)
                .padding(.top, Space.base)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack {
            Text("LCL")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.quiet)
            .accessibilityLabel("Close sidebar")
        }
        .padding(.horizontal, Space.base)
        .padding(.top, Space.tight)
    }

    private var footer: some View {
        HStack(spacing: Space.tight) {
            Button(action: onNewChat) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
            .buttonStyle(.glassPill)
            .accessibilityLabel("New chat")

            Spacer(minLength: 0)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.subheadline)
            }
            .buttonStyle(.quiet)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Space.base)
        .padding(.bottom, Space.tight)
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func row(_ title: String, systemImage: String) -> some View {
        HStack(spacing: Space.tight + 2) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 22)
            Text(title)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
    }
}
