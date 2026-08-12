import SwiftUI
import UIKit

// The design contract in code. See docs/DESIGN_SYSTEM.md — if a view disagrees with this
// file, the view is wrong.

// MARK: - Colour

enum Palette {
    /// Chat background. True black in dark mode: on OLED those pixels are off, which is
    /// what makes floating glass chrome read as genuinely floating.
    static let canvas = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .systemBackground
    })

    /// Raised surfaces step up in luminance, never in hue.
    static let canvasRaised = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.055, alpha: 1) // #0E0E10
            : .secondarySystemBackground
    })

    static let canvasRaisedHigh = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.102, alpha: 1) // #1A1A1D
            : .tertiarySystemBackground
    })

    /// User messages only. Assistant prose is never given a surface.
    static let surfaceUser = Color(.tertiarySystemFill)

    /// A single restrained hue, for interactive accents and nothing else. Teal deliberately
    /// avoids the violet/indigo gradient cliché; the dark variant is lifted because the
    /// light one fails contrast on true black.
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.373, green: 0.702, blue: 0.675, alpha: 1) // #5FB3AC
            : UIColor(red: 0.184, green: 0.435, blue: 0.420, alpha: 1) // #2F6F6B
    })

    static let separator = Color(.separator)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    static let destructive = Color(.systemRed)
    static let success = Color(.systemGreen)
    static let warning = Color(.systemOrange)

    /// Reasoning is quiet by design — never the visual focus.
    static let thinking = Color(.secondaryLabel)
}

// MARK: - Space

/// An 8pt grid with a 4pt half-step. Four values, not fifteen.
enum Space {
    static let hair: CGFloat = 4
    static let tight: CGFloat = 8
    static let base: CGFloat = 16
    static let loose: CGFloat = 24
    static let section: CGFloat = 40
}

// MARK: - Radius

enum Radius {
    static let control: CGFloat = 12
    static let surface: CGFloat = 20
    static let sheet: CGFloat = 28
    /// The chat surface when the sidebar is open.
    static let sidebarPeel: CGFloat = 36

    /// Concentric inset: a control inset by `inset` inside a surface of radius `outer`.
    /// Mismatched concentricity is the most common reason custom UI looks amateur.
    static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, outer - inset)
    }
}

// MARK: - Typography

extension View {
    /// Assistant prose. Capped line length and generous leading — it is read continuously,
    /// so it needs air. Full-width body text at large sizes is unreadable.
    func assistantProse() -> some View {
        font(.body)
            .lineSpacing(3)
            .frame(maxWidth: 620, alignment: .leading)
    }

    /// Timestamps, counts, token figures. Monospaced digits so streaming counters do not
    /// jitter as they change.
    func metadataText() -> some View {
        font(.footnote)
            .monospacedDigit()
            .foregroundStyle(Palette.textTertiary)
    }

    /// Guarantees a 44×44pt hit target even when the glyph inside is smaller.
    func minimumHitTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Layout constants

enum Layout {
    /// Screen gutter.
    static let gutter = Space.base
    /// Composer stops growing here and scrolls internally instead.
    static let composerMaxHeightFraction: CGFloat = 0.4
    /// Sidebar width, capped so it never swallows the whole screen on a small iPhone.
    static func sidebarWidth(for screenWidth: CGFloat) -> CGFloat {
        min(320, screenWidth * 0.82)
    }
}
