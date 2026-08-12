import SwiftUI

/// Every animation in LCL comes from here. Nothing else calls `.animation` with a literal
/// curve — see docs/DESIGN_SYSTEM.md §6.
///
/// Springs only. Springs describe physical motion; ease curves describe nothing, and
/// `.easeInOut` is the clearest tell of non-native UI.
enum MotionSystem {
    /// No overshoot. Button presses, immediate state flips.
    static let instant = Animation.spring(response: 0.22, dampingFraction: 1.0)
    /// The default.
    static let standard = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// Large surfaces, where a faster spring would feel frantic.
    static let gentle = Animation.spring(response: 0.45, dampingFraction: 0.90)
    /// Drawer settle.
    static let sidebar = Animation.spring(response: 0.38, dampingFraction: 0.85)
    /// Slight bounce, for a completion moment.
    static let pop = Animation.spring(response: 0.28, dampingFraction: 0.68)

    /// Under Reduce Motion the interface becomes still, not broken: movement and scale go,
    /// opacity cross-fades stay.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : animation
    }
}

extension View {
    /// Applies an animation that automatically degrades under Reduce Motion.
    func lclAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ResolvedAnimation(animation: animation, value: value))
    }

    /// Fades and rises into place **once**, on first appearance.
    ///
    /// Opacity plus a 6pt rise, no scale: scaling text on arrival reads as a web animation
    /// (docs/DESIGN_SYSTEM.md §6). Deliberately once-only — during streaming the trailing
    /// block re-renders constantly, and anything driven by content would re-animate on every
    /// token.
    func appearOnce(delay: Double = 0) -> some View {
        modifier(AppearOnce(delay: delay))
    }
}

private struct ResolvedAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(MotionSystem.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

private struct AppearOnce: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            // Under Reduce Motion the movement goes and the cross-fade stays: still, not
            // broken.
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                guard !shown else { return }
                withAnimation(
                    MotionSystem.resolved(MotionSystem.standard, reduceMotion: reduceMotion)
                        .delay(delay)
                ) {
                    shown = true
                }
            }
    }
}
