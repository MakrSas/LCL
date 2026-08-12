import SwiftUI

/// LCL — LoCaL.
///
/// Step 0 of Phase 1: the app exists and builds. Nothing more is claimed here.
/// See docs/PHASE_1_PLAN.md — the DesignSystem lands before any real screen, so this
/// root deliberately contains no chrome, no cards, and no placeholder controls
/// (docs/PRODUCT_SPEC.md: "no fake UI").
@main
struct LCLApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
