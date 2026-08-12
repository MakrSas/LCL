import SwiftUI

/// The wordmark on a bare canvas.
///
/// This is the eventual empty state (docs/PRODUCT_SPEC.md §4), and for Step 0 it is the
/// whole app. It uses system typography and semantic colours only, so it is already
/// correct in light and dark and at every Dynamic Type size — which is the point: even
/// the placeholder obeys the design contract.
struct RootView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            Text("LCL")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

#Preview {
    RootView()
}
