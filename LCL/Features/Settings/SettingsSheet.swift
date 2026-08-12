import SwiftUI

/// Deliberately tiny: it contains the one setting that exists. Rows for Models, Chat,
/// Context, Web, GitHub and the rest appear when those features do — an empty settings tree
/// is exactly the fake UI docs/PRODUCT_SPEC.md forbids.
struct SettingsSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AccentChoice.allCases) { choice in
                        Button {
                            settings.accent = choice
                        } label: {
                            HStack(spacing: Space.base) {
                                Circle()
                                    .fill(choice.color)
                                    .frame(width: 22, height: 22)
                                Text(choice.name)
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer()
                                if settings.accent == choice {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(choice.color)
                                        .transition(.opacity)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Accent")
                } footer: {
                    Text("Used for interactive accents only — never for surfaces or text.")
                }
            }
            .navigationTitle("Appearance")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .lclAnimation(MotionSystem.standard, value: settings.accent)
            .haptic(.selection, trigger: settings.accent)
        }
    }
}
