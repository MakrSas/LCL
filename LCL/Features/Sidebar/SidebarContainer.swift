import SwiftUI

/// An interactive, finger-following drawer. The sidebar sits underneath; the chat slides off
/// it.
///
/// `NavigationSplitView` collapses to a stack on iPhone and gives no drag-to-reveal drawer,
/// so this is a custom container (docs/PRODUCT_SPEC.md §6).
///
/// The content genuinely narrows as the drawer opens — not a fixed-width view sliding mostly
/// off-screen. That distinction is what lets its trailing edge round to match the reveal edge,
/// rather than showing the flat, unrounded *middle* of an oversized rectangle (see the `.frame`
/// call in `body`). It is a real width change, not a `.scaleEffect` — `.scaleEffect` is cheaper
/// but visually squashes everything inside (icons go elliptical, text compresses), which reads
/// as broken in a way an actual reflow doesn't.
///
/// Corner radii are asymmetric: small on the leading edge (`Radius.sidebarReveal`), where the
/// toolbar toggle and composer's `+` actually live, and full device-corner size on the trailing
/// edge (`Radius.deviceCorner`), where nothing does. A single large radius on the leading side
/// clips straight through those controls.
///
/// The narrowed width itself is applied only when settled or animating a settle — never while a
/// finger is down. See the `.frame` call in `body` for why: resizing a `NavigationStack`'s real
/// layout width every frame while it's simultaneously the live target of a touch is a plausible
/// source of drag stutter, and it's the reason there is a difference between "actively dragging"
/// and "at rest / settling" in this file at all.
///
/// Two other things tried here were real defects, not stylistic misses, and stayed removed:
///   • parallax on a *static* drawer left a black gap between it and the content
///   • shadow forces the whole surface to re-rasterise every frame
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
        // .ignoresSafeArea() on the reader itself, not just on children. Without it,
        // GeometryReader reports the safe-area-inset size (shorter than the true screen), while
        // content's own .ignoresSafeArea() tries to bleed to the real edges independently of
        // that smaller frame. The offset/clipShape here operate in the READER's coordinate
        // space, so the top/bottom strips inside the safe-area inset ended up outside that
        // space entirely — static, unclipped, never sliding with the rest of the screen. This
        // is what produced the gaps and the flat (non-rounded) edge once fully open: those
        // strips were never part of the animated geometry to begin with.
        GeometryReader { proxy in
            let width = Layout.sidebarWidth(for: proxy.size.width)
            let progress = progress(width: width)
            // `proxy.safeAreaInsets` still reports the true device insets even though the
            // reader itself ignores them for layout — this is the standard way to get a
            // full-bleed frame while still knowing where the notch/home-indicator are, so a
            // plain view (unlike NavigationStack's own toolbar, which insets itself
            // automatically) can be told explicitly to stay clear of them.
            let insets = proxy.safeAreaInsets
            let isInteractivelyDragging = isHorizontalDrag == true
            let narrowedWidth = proxy.size.width - width * progress

            ZStack(alignment: .leading) {
                // Underneath, and static: no parallax, so there is never a gap between it and
                // the content for the container's black base to show through.
                //
                // Padding first, background after: `sidebar` (a plain VStack, not a
                // NavigationStack with its own toolbar) needs to be told explicitly to stay
                // clear of the status bar / home indicator now that its ancestor is full-bleed.
                // The background is applied to the already-padded view with
                // `ignoresSafeAreaEdges: .vertical`, so the grey fill still reaches the true
                // top and bottom edges — only the rows/buttons inside stay inset.
                sidebar
                    .padding(.top, insets.top)
                    .padding(.bottom, insets.bottom)
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
                    // Narrowed width, but ONLY when settled or animating a settle — never while
                    // a finger is actively down. Two reasons:
                    //
                    // 1. `nil` (no constraint at all) when progress == 0, not "a frame that
                    //    happens to equal full width". Merely HAVING a `.frame(width:)` modifier
                    //    present — regardless of its value — was enough to make NavigationStack
                    //    stop self-inseting its own toolbar under the status bar. `nil` genuinely
                    //    removes the modifier's effect, matching pre-fix behaviour exactly at
                    //    rest, where nothing was ever broken.
                    // 2. While `isInteractivelyDragging`, content stays full width with plain
                    //    offset — the same mechanics already proven smooth. Reflowing a
                    //    NavigationStack's real layout width every frame while it's ALSO the
                    //    live target of an active touch is a plausible source of the stutter
                    //    reported when closing from deep inside the narrow sliver: the touch
                    //    system and the resizing view were fighting over the same moving
                    //    boundary. The narrowed, two-sided-rounded shape only appears once the
                    //    finger lifts, animated in by the same spring as the position settle.
                    .frame(width: isInteractivelyDragging || progress == 0 ? nil : narrowedWidth)
                    // Asymmetric on purpose. The leading corners sit where the toolbar toggle
                    // and composer's `+` live, so they stay small (Radius.sidebarReveal) to
                    // clear those controls. The trailing corners, once narrowed, coincide with
                    // the screen's own true right edge — nothing sits there, so they can use the
                    // full device-corner radius without clipping anything.
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: Radius.sidebarReveal,
                            bottomLeadingRadius: Radius.sidebarReveal,
                            bottomTrailingRadius: Radius.deviceCorner,
                            topTrailingRadius: Radius.deviceCorner,
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
        .ignoresSafeArea()
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
