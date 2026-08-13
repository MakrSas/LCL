import Foundation

/// Pure geometry math for the sidebar reveal drawer, extracted specifically so it can be unit
/// tested without a device, a simulator, or any SwiftUI rendering at all. Every one of tonight's
/// sidebar regressions — the drag stutter, the flat trailing edge, the touch lock-up — could only
/// be caught by shipping a build and reading a screenshot from a phone. None of them needed a
/// device to catch; they were all wrong arithmetic or wrong state, reachable from here.
enum SidebarGeometry {
    /// 0 (closed) to 1 (open), clamped. `width` is the sidebar's own width, which for this
    /// drawer doubles as the total drag distance from closed to open.
    static func progress(isOpen: Bool, dragTranslation: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let base = isOpen ? width : 0
        return min(max((base + dragTranslation) / width, 0), 1)
    }

    /// The chat's visible (masked) width at a given point in the reveal — the full screen width
    /// when closed, shrinking to `screenWidth - sidebarWidth` once fully open. Combined with the
    /// same `sidebarWidth * progress` offset used to position the chat, this keeps its trailing
    /// edge pinned exactly at the screen's true right edge throughout, which is the entire reason
    /// `RevealClip` can round that edge correctly.
    static func narrowedWidth(screenWidth: CGFloat, sidebarWidth: CGFloat, progress: CGFloat) -> CGFloat {
        screenWidth - sidebarWidth * progress
    }

    /// Whether a released drag should settle the drawer open, given a velocity-aware predicted
    /// end translation.
    ///
    /// `predictedEndTranslation` and `translationBaseline` share the same touch-down coordinate
    /// origin (both come from the same `DragGesture.Value`), so both need the identical baseline
    /// correction — `DragGesture`'s `translation` already carries up to `minimumDistance` of
    /// travel on its first delivered event, measured from touch-down rather than from wherever
    /// the gesture actually started being recognised. Skipping this correction here specifically
    /// (having already applied it to live `dragTranslation` elsewhere) would make the open/close
    /// decision inconsistent with what was actually on screen — most visible on short, fast
    /// flicks near the halfway threshold, which is exactly the case a velocity-aware decision
    /// exists to handle well.
    static func shouldOpen(
        isOpen: Bool,
        predictedEndTranslation: CGFloat,
        translationBaseline: CGFloat,
        width: CGFloat
    ) -> Bool {
        guard width > 0 else { return isOpen }
        let base = isOpen ? width : 0
        let predicted = base + (predictedEndTranslation - translationBaseline)
        return predicted > width * 0.5
    }
}
