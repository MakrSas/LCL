import SwiftUI

/// An interactive, finger-following drawer. The sidebar sits underneath; the chat slides off
/// it.
///
/// `NavigationSplitView` collapses to a stack on iPhone and gives no drag-to-reveal drawer,
/// so this is a custom container (docs/PRODUCT_SPEC.md §6).
///
/// Content's LAYOUT is always full width — its `NavigationStack`, toolbar and composer never
/// know the drawer exists, and never reflow. Only the VISIBLE portion narrows, via a clip mask
/// (`RevealClip`, below `body`), not a frame change. That distinction went through two wrong
/// attempts before landing here:
///   • pure offset (no narrowing at all): content's true trailing edge — the one with rounded
///     corners — slides off-screen the instant it's offset, so what's visible at the screen's
///     true right edge is the flat, unrounded *middle* of an oversized rectangle.
///   • narrowing content's actual `.frame(width:)`: fixes the rounding, but forces
///     `NavigationStack` to relay out its toolbar in as little as ~70pt once mostly closed by
///     the drawer — not enough room, so the title and toggle button overlapped and iOS started
///     collapsing toolbar items into an overflow "..." button. A real layout change was the
///     wrong tool even before considering its per-frame cost during a drag.
/// `RevealClip` reads as a real, narrower "floating card" without content ever finding out its
/// own width changed.
///
/// Corner radii are asymmetric: small on the leading edge (`Radius.sidebarReveal`), where the
/// toolbar toggle and composer's `+` actually live, and full device-corner size on the trailing
/// edge (`Radius.deviceCorner`), where nothing does. A single large radius on the leading side
/// clips straight through those controls.
///
/// Three other things tried here were real defects, not stylistic misses, and stayed removed:
///   • parallax on a *static* drawer left a black gap between it and the content
///   • shadow forces the whole surface to re-rasterise every frame
///   • `.scaleEffect` (as an alternative to narrowing) is cheaper than a real width change, but
///     visually squashes everything inside non-uniformly — icons go elliptical, text
///     compresses — which reads as broken in a way a correctly-masked reveal doesn't
struct SidebarContainer<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    /// Captured by `AppRoot` from an ordinary `GeometryReader` that does **not**
    /// `.ignoresSafeArea()`, and handed down as plain constants — see the call site for why.
    /// This container only ever consumes them; it must never try to re-derive them from its
    /// own (necessarily full-bleed) reader below.
    let topInset: CGFloat
    let bottomInset: CGFloat
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
        //
        // Because this reader ignores the safe area, its OWN `proxy.safeAreaInsets` is not
        // used for anything — two directly-fetched sources gave opposite answers for whether
        // it reports zero or the true device insets once a reader ignores its own safe area,
        // and rather than trust either, `topInset`/`bottomInset` are captured by `AppRoot`
        // from a separate, ordinary reader that never ignores anything, and simply passed in.
        GeometryReader { proxy in
            let width = Layout.sidebarWidth(for: proxy.size.width)
            let progress = SidebarGeometry.progress(isOpen: isOpen, dragTranslation: dragTranslation, width: width)
            let narrowedWidth = SidebarGeometry.narrowedWidth(
                screenWidth: proxy.size.width,
                sidebarWidth: width,
                progress: progress
            )

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
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
                    .frame(width: width)
                    .background(Palette.canvasRaised, ignoresSafeAreaEdges: .vertical)
                    .accessibilityHidden(progress < 0.9)

                content
                    // Top only. The composer already reserves its own bottom space via
                    // `.safeAreaInset(edge: .bottom)` inside ChatView — padding the bottom
                    // here too, on top of that, would double the gap above it. No confirmed
                    // evidence the bottom is actually broken, unlike the top.
                    .padding(.top, topInset)
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
                    // NEVER constrain content's actual frame/layout width — that was the bug in
                    // the previous attempt. Narrowing the real frame forced NavigationStack to
                    // relayout its toolbar in as little as ~70pt, which isn't enough room:
                    // the title and toggle button overlapped, and iOS started collapsing
                    // toolbar items into an overflow "..." button. Content is always laid out
                    // at its full, unconstrained width — the toolbar and composer never know
                    // the drawer exists — and only the VISIBLE, CLIPPED portion narrows.
                    //
                    // `RevealClip` (below) ignores the rect SwiftUI offers it (content's full
                    // width) and builds its own path at exactly `narrowedWidth`, anchored to
                    // content's leading edge — which, after the same offset used below, lands
                    // precisely on the true screen edge. Because this is a mask, not a layout
                    // change, it costs nothing extra during an active drag either: no more
                    // reason to special-case interactive dragging separately from settling.
                    .clipShape(
                        RevealClip(
                            width: narrowedWidth,
                            leadingRadius: Radius.sidebarReveal,
                            trailingRadius: Radius.deviceCorner
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
                let liveProgress = SidebarGeometry.progress(isOpen: isOpen, dragTranslation: dragTranslation, width: width)
                latch.update(isPast: liveProgress > 0.5)
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

                // Velocity-aware: a fast flick wins over distance travelled. See
                // `SidebarGeometry.shouldOpen` for why the baseline correction matters here too.
                let shouldOpen = SidebarGeometry.shouldOpen(
                    isOpen: isOpen,
                    predictedEndTranslation: value.predictedEndTranslation.width,
                    translationBaseline: translationBaseline,
                    width: width
                )

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

/// Clips to a `width`-wide slice of the view's LEADING edge, asymmetrically rounded — a mask,
/// deliberately not a `.frame` change (see the call site in `SidebarContainer.body`).
///
/// A plain `.clipShape(UnevenRoundedRectangle(...))` sizes itself to whatever view it's applied
/// to, which is exactly what we don't want here: content stays laid out at its full width, and
/// only a narrower slice of it should be visibly rounded. `Shape.path(in:)` receives the
/// containing view's rect regardless — this type deliberately ignores its offered `width` and
/// substitutes its own, using only `rect.height` and `rect.minY`.
///
/// Not `private`: `SidebarGeometryTests` constructs it directly to assert it actually ignores
/// the offered rect's width, which is the entire point of the type and the exact thing a typo
/// here would silently break.
struct RevealClip: Shape {
    let width: CGFloat
    let leadingRadius: CGFloat
    let trailingRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let slice = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        return UnevenRoundedRectangle(
            topLeadingRadius: leadingRadius,
            bottomLeadingRadius: leadingRadius,
            bottomTrailingRadius: trailingRadius,
            topTrailingRadius: trailingRadius,
            style: .continuous
        ).path(in: slice)
    }
}
