import SwiftUI

/// An interactive, finger-following drawer. The sidebar sits underneath; the chat slides off
/// it.
///
/// `NavigationSplitView` collapses to a stack on iPhone and gives no drag-to-reveal drawer,
/// so this is a custom container (docs/PRODUCT_SPEC.md §6).
///
/// Deliberately plain: offset and a dim, nothing else. Every decorative addition tried here —
/// parallax, corner radius, scale, shadow — produced a visible defect or cost real frames:
///   • parallax left a black gap between the drawer and the content
///   • a large corner radius clipped through the toolbar button
///   • scale and shadow forced the whole subtree to re-rasterise each frame
struct SidebarContainer<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragTranslation: CGFloat = 0
    /// Decided once per gesture. Re-testing per event dropped updates on a diagonal drag.
    @State private var isHorizontalDrag: Bool?

    /// `DragGesture.Value.translation` is measured from the initial touch, not from wherever
    /// `minimumDistance` was cleared — so the first delivered event already carries up to
    /// `minimumDistance` of travel baked in. Applied verbatim, that pops the drawer a few
    /// points the instant the gesture is recognised, ahead of the finger. This is that first
    /// sample, captured once and subtracted from every later one, so tracking starts exactly
    /// under the fingertip.
    @State private var translationBaseline: CGFloat = 0

    @State private var latch = ThresholdLatch()

    /// `@State`, deliberately not `@GestureState`, for all of the above. `@GestureState`
    /// auto-resets when a gesture ends, in its own transaction separate from the
    /// `withAnimation` block in `onEnded` — which is precisely the mechanism behind the
    /// already-fixed bug where the settle animation visibly replayed on release.

    private let edgeGrabWidth: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let width = Layout.sidebarWidth(for: proxy.size.width)
            let progress = progress(width: width)

            ZStack(alignment: .leading) {
                // Underneath, and static: no parallax, so there is never a gap between it and
                // the content for the container's black base to show through.
                sidebar
                    .frame(width: width)
                    .background(Palette.canvasRaised, ignoresSafeAreaEdges: .vertical)
                    .accessibilityHidden(progress < 0.9)

                content
                    .disabled(isOpen)
                    .overlay {
                        Color.black
                            .opacity(0.35 * progress)
                            .ignoresSafeArea()
                            // Gated on `isOpen`, NOT on progress. This is the drag-stutter fix.
                            //
                            // The edge strip below is gated on `!isOpen`, so driving both from
                            // the same boolean makes exactly one of them hit-testable at any
                            // moment. With the previous `progress > 0.5` gate there was a real
                            // overlap window: during an opening drag `isOpen` stays false until
                            // release, so the edge strip remained mounted while this overlay
                            // became eligible halfway through — two separately recognised
                            // gestures competing for one touch, writing to the same
                            // `dragTranslation` from *different* translation origins. That made
                            // the offset snap from ~150pt to ~5pt within a single frame, right
                            // around the halfway mark of every drag.
                            //
                            // It also still fixes the lock-up: an interrupted gesture can no
                            // longer leave an invisible full-screen view eating every touch.
                            .allowsHitTesting(isOpen)
                            .onTapGesture { setOpen(false) }
                            .gesture(drag(width: width))
                            .accessibilityHidden(!isOpen)
                            .accessibilityLabel("Close sidebar")
                            .accessibilityAddTraits(.isButton)
                    }
                    // Rounded while sliding, at surface radius rather than the larger peel
                    // radius: a 36pt curve cut through the toolbar button sitting in that
                    // corner, which is why this was removed before.
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: Radius.surface * progress,
                            style: .continuous
                        )
                    )
                    .offset(x: width * progress)
            }
            .overlay(alignment: .leading) {
                // Edge grab strip, only when closed. Keeping the gesture off the transcript
                // means it never competes with vertical scrolling.
                if !isOpen {
                    Color.clear
                        .frame(width: edgeGrabWidth)
                        .contentShape(Rectangle())
                        .gesture(drag(width: width))
                        .ignoresSafeArea()
                }
            }
            .haptic(.sidebarThreshold, trigger: latch.crossings)
        }
    }

    // MARK: - Geometry

    private func progress(width: CGFloat) -> CGFloat {
        let base = isOpen ? width : 0
        return min(max((base + dragTranslation) / width, 0), 1)
    }

    // MARK: - Gesture

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if isHorizontalDrag == nil {
                    isHorizontalDrag = abs(value.translation.width) > abs(value.translation.height)
                    // Whatever translation has already accumulated becomes this gesture's zero.
                    translationBaseline = value.translation.width
                    if isHorizontalDrag == true { latch.reset(isPast: isOpen) }
                }
                // Once the gesture is claimed as horizontal, follow every event. Re-deciding
                // per event dropped updates mid-drag and the offset jumped when they resumed.
                guard isHorizontalDrag == true else { return }
                dragTranslation = value.translation.width - translationBaseline
                latch.update(isPast: progress(width: width) > 0.5)
            }
            .onEnded { value in
                let wasHorizontal = isHorizontalDrag == true
                isHorizontalDrag = nil

                guard wasHorizontal else {
                    // Always clear, even for a gesture we ignored: a stale translation is what
                    // left the app unresponsive.
                    dragTranslation = 0
                    return
                }

                // Velocity-aware: a fast flick wins over distance travelled.
                // `predictedEndTranslation` shares the same touch-down origin as `translation`,
                // so it needs the identical baseline correction — otherwise this decision is
                // off by a constant from what was actually on screen, which matters for short
                // fast flicks near the threshold.
                let predicted = (isOpen ? width : 0)
                    + (value.predictedEndTranslation.width - translationBaseline)
                let shouldOpen = predicted > width * 0.5

                // Both inside ONE animation block. Resetting the translation outside it snapped
                // `progress` back instantly and only then ran the spring, which read as the
                // animation playing a second time on release.
                withAnimation(MotionSystem.resolved(MotionSystem.sidebar, reduceMotion: reduceMotion)) {
                    dragTranslation = 0
                    isOpen = shouldOpen
                }
                latch.reset(isPast: shouldOpen)
            }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(MotionSystem.resolved(MotionSystem.sidebar, reduceMotion: reduceMotion)) {
            dragTranslation = 0
            isOpen = open
        }
        latch.reset(isPast: open)
    }
}
