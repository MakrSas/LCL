import SwiftUI

/// The only place in LCL that applies Liquid Glass.
///
/// Two reasons it is a single file. Design: glass means "this floats above content", and
/// scattering it destroys that meaning (docs/DESIGN_SYSTEM.md §5). Practical: the glass API
/// is new, so if a signature is wrong exactly one file fails to compile.
///
/// Glass is for floating chrome — composer, toolbars, overlays, contextual controls. Never
/// behind message text, list rows, code blocks, or anything containing a paragraph.
struct GlassCluster<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let cornerRadius: CGFloat
    private let spacing: CGFloat?
    private let interactive: Bool
    private let content: Content

    init(
        cornerRadius: CGFloat = Radius.sheet,
        spacing: CGFloat? = Space.tight,
        interactive: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.spacing = spacing
        self.interactive = interactive
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        if reduceTransparency {
            // A real code path, not an afterthought: opaque surface plus a hairline so the
            // edge is still legible without translucency doing that job.
            content
                .background(Palette.canvasRaisedHigh, in: shape)
                .overlay(shape.strokeBorder(Palette.separator, lineWidth: 0.5))
        } else {
            GlassEffectContainer(spacing: spacing) {
                content
                    .glassEffect(
                        interactive ? .regular.interactive() : .regular,
                        in: shape
                    )
            }
        }
    }
}

// MARK: - Buttons

/// Quiet by default: a glyph or short label that reads as a control without shouting.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.textSecondary)
            .minimumHitTarget()
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(
                MotionSystem.resolved(MotionSystem.instant, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// The accented affirmative action. One accent colour in the app, used here.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.white : Palette.textTertiary)
            .padding(.horizontal, Space.base)
            .frame(minHeight: 44)
            .background(
                isEnabled ? Palette.accent : Palette.surfaceUser,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(
                MotionSystem.resolved(MotionSystem.instant, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var lclPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
