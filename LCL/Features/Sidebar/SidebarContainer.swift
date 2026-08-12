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
    /// Decided once per gesture. Re-testing per event skipped updates on a diagonal drag,
    /// which is what made manual dragging stutter.
    @State private var isHorizontalDrag: Bool?
    @State private var latch = ThresholdLatch()

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
                            // The lock-up fix. This overlay used to swallow every touch
                            // whenever `progress` was left even slightly above zero by an
                            // interrupted gesture — invisible, but covering the screen. It can
                            // only take a touch once the drawer is genuinely open.
                            .allowsHitTesting(progress > 0.5)
                            .onTapGesture { setOpen(false) }
                            .gesture(drag(width: width))
                            .accessibilityHidden(progress < 0.5)
                            .accessibilityLabel("Close sidebar")
                            .accessibilityAddTraits(.isButton)
                    }
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
                    if isHorizontalDrag == true { latch.reset(isPast: isOpen) }
                }
                // Once the gesture is claimed as horizontal, follow every event. Re-deciding
                // per event dropped updates mid-drag and the offset jumped when they resumed.
                guard isHorizontalDrag == true else { return }
                dragTranslation = value.translation.width
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
                let predicted = (isOpen ? width : 0) + value.predictedEndTranslation.width
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
