import SwiftUI

/// LCL — LoCaL.
///
/// Phase 1 (docs/PHASE_1_PLAN.md): DesignSystem, interactive sidebar, chat, floating
/// composer and streaming, running on `MockModelProvider`. Gemma 4 E2B lands in Step 7
/// behind the same `ModelProvider` protocol, with no view changing.
@main
struct LCLApp: App {
    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}
