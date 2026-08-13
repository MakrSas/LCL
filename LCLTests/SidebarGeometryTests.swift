import XCTest
import SwiftUI
@testable import LCL

/// Every one of tonight's sidebar regressions — the drag stutter, the flat trailing edge, the
/// touch lock-up — could only be caught by shipping a build and reading a screenshot from a
/// phone. None of them actually needed a device to catch; they were all wrong arithmetic or
/// wrong state, reachable from `SidebarGeometry` and `RevealClip` directly. These tests exist so
/// the next regression like that fails in CI instead.
final class SidebarGeometryTests: XCTestCase {

    private let sidebarWidth: CGFloat = 320
    private let screenWidth: CGFloat = 390

    // MARK: - progress

    func testProgressAtRestClosed() {
        let p = SidebarGeometry.progress(isOpen: false, dragTranslation: 0, width: sidebarWidth)
        XCTAssertEqual(p, 0)
    }

    func testProgressAtRestOpen() {
        let p = SidebarGeometry.progress(isOpen: true, dragTranslation: 0, width: sidebarWidth)
        XCTAssertEqual(p, 1)
    }

    func testProgressMidOpeningDrag() {
        let p = SidebarGeometry.progress(isOpen: false, dragTranslation: sidebarWidth / 2, width: sidebarWidth)
        XCTAssertEqual(p, 0.5, accuracy: 0.0001)
    }

    func testProgressMidClosingDrag() {
        let p = SidebarGeometry.progress(isOpen: true, dragTranslation: -sidebarWidth / 2, width: sidebarWidth)
        XCTAssertEqual(p, 0.5, accuracy: 0.0001)
    }

    /// A finger dragged well past the sidebar's own width must not report more than fully open —
    /// this clamp is what keeps `narrowedWidth` from going negative.
    func testProgressClampsAboveOne() {
        let p = SidebarGeometry.progress(isOpen: true, dragTranslation: 1000, width: sidebarWidth)
        XCTAssertEqual(p, 1)
    }

    func testProgressClampsBelowZero() {
        let p = SidebarGeometry.progress(isOpen: false, dragTranslation: -1000, width: sidebarWidth)
        XCTAssertEqual(p, 0)
    }

    /// `Layout.sidebarWidth` should never actually return 0, but the geometry math must not
    /// divide by it blindly if it somehow did.
    func testProgressGuardsZeroWidth() {
        let p = SidebarGeometry.progress(isOpen: true, dragTranslation: 50, width: 0)
        XCTAssertEqual(p, 0)
    }

    // MARK: - narrowedWidth

    func testNarrowedWidthAtClosedIsFullScreen() {
        let w = SidebarGeometry.narrowedWidth(screenWidth: screenWidth, sidebarWidth: sidebarWidth, progress: 0)
        XCTAssertEqual(w, screenWidth)
    }

    /// The property the whole `RevealClip` design depends on: at full open, content's visible
    /// width must equal exactly `screenWidth - sidebarWidth`, so that combined with the same
    /// `sidebarWidth * progress` offset used to position it, its trailing edge lands exactly on
    /// the screen's true right edge — never short of it (a gap) and never past it (off-screen,
    /// which is the original "flat edge" bug).
    func testNarrowedWidthAtOpenMatchesVisibleSliver() {
        let w = SidebarGeometry.narrowedWidth(screenWidth: screenWidth, sidebarWidth: sidebarWidth, progress: 1)
        XCTAssertEqual(w, screenWidth - sidebarWidth)

        // The property stated above, checked directly rather than assumed:
        let offset = sidebarWidth * 1
        XCTAssertEqual(offset + w, screenWidth, "trailing edge must land exactly on the true screen edge")
    }

    func testNarrowedWidthInterpolatesLinearly() {
        let w = SidebarGeometry.narrowedWidth(screenWidth: screenWidth, sidebarWidth: sidebarWidth, progress: 0.5)
        XCTAssertEqual(w, screenWidth - sidebarWidth * 0.5)
    }

    // MARK: - shouldOpen

    func testShouldOpenPastThresholdWhileClosed() {
        let result = SidebarGeometry.shouldOpen(
            isOpen: false,
            predictedEndTranslation: sidebarWidth * 0.6,
            translationBaseline: 0,
            width: sidebarWidth
        )
        XCTAssertTrue(result)
    }

    func testShouldStayClosedBelowThreshold() {
        let result = SidebarGeometry.shouldOpen(
            isOpen: false,
            predictedEndTranslation: sidebarWidth * 0.3,
            translationBaseline: 0,
            width: sidebarWidth
        )
        XCTAssertFalse(result)
    }

    func testShouldCloseWhenFlickedPastThresholdWhileOpen() {
        let result = SidebarGeometry.shouldOpen(
            isOpen: true,
            predictedEndTranslation: -sidebarWidth * 0.6,
            translationBaseline: 0,
            width: sidebarWidth
        )
        XCTAssertFalse(result)
    }

    func testShouldStayOpenBelowClosingThreshold() {
        let result = SidebarGeometry.shouldOpen(
            isOpen: true,
            predictedEndTranslation: -sidebarWidth * 0.3,
            translationBaseline: 0,
            width: sidebarWidth
        )
        XCTAssertTrue(result)
    }

    /// Reproduces the exact shape of the `minimumDistance` bug: `predictedEndTranslation` still
    /// carries the baseline offset that was already subtracted from live `dragTranslation`
    /// elsewhere. Chosen so the corrected and uncorrected answers actually DISAGREE — a case
    /// close enough to the threshold that including the baseline flips the decision — so this
    /// test only passes if the subtraction is really happening, not just present in the code.
    func testShouldOpenAppliesBaselineCorrection() {
        let threshold = sidebarWidth * 0.5 // 160
        let baseline: CGFloat = 8          // minimumDistance
        let rawPredicted = threshold - 5 + baseline // 163: below threshold once corrected, above if not

        let corrected = SidebarGeometry.shouldOpen(
            isOpen: false,
            predictedEndTranslation: rawPredicted,
            translationBaseline: baseline,
            width: sidebarWidth
        )
        XCTAssertFalse(corrected, "should read as below threshold once the baseline is subtracted")

        // Same inputs, deliberately uncorrected (baseline: 0) — proves this is a real behavioural
        // difference, not just an unused parameter.
        let uncorrected = SidebarGeometry.shouldOpen(
            isOpen: false,
            predictedEndTranslation: rawPredicted,
            translationBaseline: 0,
            width: sidebarWidth
        )
        XCTAssertTrue(uncorrected, "sanity check: without correction this same input reads as past threshold")
    }

    func testShouldOpenGuardsZeroWidth() {
        XCTAssertTrue(SidebarGeometry.shouldOpen(isOpen: true, predictedEndTranslation: 0, translationBaseline: 0, width: 0))
        XCTAssertFalse(SidebarGeometry.shouldOpen(isOpen: false, predictedEndTranslation: 999, translationBaseline: 0, width: 0))
    }

    // MARK: - RevealClip

    /// The one assertion that would have caught the original mistake immediately: `RevealClip`
    /// must clip to ITS OWN `width`, not to whatever (much wider) rect the containing view
    /// offers it. This is the entire mechanism that lets content stay laid out at full width
    /// while only a narrow slice is visibly rounded.
    func testRevealClipIgnoresOfferedRectWidth() {
        let clip = RevealClip(width: 100, leadingRadius: 12, trailingRadius: 55)
        let offered = CGRect(x: 0, y: 0, width: screenWidth, height: 800)

        let bounds = clip.path(in: offered).boundingRect

        XCTAssertEqual(bounds.width, 100, accuracy: 0.5)
        XCTAssertNotEqual(bounds.width, offered.width)
    }

    func testRevealClipAnchorsToLeadingEdgeOfOfferedRect() {
        let clip = RevealClip(width: 100, leadingRadius: 12, trailingRadius: 55)
        let offered = CGRect(x: 0, y: 0, width: screenWidth, height: 800)

        let bounds = clip.path(in: offered).boundingRect

        XCTAssertEqual(bounds.minX, offered.minX, accuracy: 0.5)
    }

    func testRevealClipUsesFullOfferedHeight() {
        let clip = RevealClip(width: 100, leadingRadius: 12, trailingRadius: 55)
        let offered = CGRect(x: 0, y: 0, width: screenWidth, height: 800)

        let bounds = clip.path(in: offered).boundingRect

        XCTAssertEqual(bounds.height, offered.height, accuracy: 0.5)
    }
}
