import SwiftUI

/// An interactive, finger-following drawer.
///
/// `NavigationSplitView` collapses to a stack on iPhone and gives no drag-to-reveal drawer,
/// so this is a custom container (docs/PRODUCT_SPEC.md §6).
///
/// The details that decide whether it feels native:
///   • 1:1 with the finger, with **no animation while dragging** — animating during a drag
///     is what makes a drawer feel laggy.
///   • velocity-aware settle via `predictedEndTranslation`, so a fast flick opens even from
///     a short distance.
///   • interruptible: the settle spring can be grabbed mid-flight.
///   • one latched haptic at the threshold, so wobbling across it does not chatter.
///   • a real button for VoiceOver, because an edge swipe is not discoverable.
struct SidebarContainer<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false
    @State private var latch = ThresholdLatch()

    private let edgeGrabWidth: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let width = Layout.sidebarWidth(for: proxy.size.width)
            let progress = progress(width: width)

            ZStack(alignment: .leading) {
                // True black all the way into the safe areas. Anything lighter here shows as
                // bands above and below the content once it is inset or rounded.
                Palette.canvas
                    .ignoresSafeArea()

                sidebar
                    .frame(width: width)
                    // Its own raised surface. The container base is true black so no band
                    // shows at the content's edges, which left the sidebar with no background
                    // of its own until this.
                    .background(Palette.canvasRaised, ignoresSafeAreaEdges: .vertical)
                    .opacity(reduceMotion ? (progress > 0.5 ? 1 : 0) : progress)
                    // Slight parallax: the sidebar trails the content rather than moving
                    // with it, which reads as depth instead of a sliding sheet.
                    .offset(x: reduceMotion ? 0 : -width * 0.22 * (1 - progress))
                    .accessibilityHidden(progress < 0.9)

                contentSurface(width: width, progress: progress)
            }
            .contentShape(Rectangle())
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

    private func contentSurface(width: CGFloat, progress: CGFloat) -> some View {
        content
            .disabled(isOpen)
            .overlay {
                if progress > 0 {
                    Color.black
                        .opacity(0.38 * progress)
                        .ignoresSafeArea()
                        .onTapGesture { setOpen(false) }
                        .gesture(drag(width: width))
                        .accessibilityLabel("Close sidebar")
                        .accessibilityAddTraits(.isButton)
                }
            }
            // Offset ONLY. This is the fix for the remaining stutter.
            //
            // A translation is a cheap GPU transform. The previous version also animated a
            // `clipShape` corner radius and a `scaleEffect` over the live chat hierarchy —
            // a NavigationStack containing a ScrollView — which forced the entire subtree to
            // re-rasterise on every frame. That cost far more than the peel effect was worth,
            // so the peel is gone.
            .offset(x: width * progress)
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
                // Ignore drags that are clearly vertical.
                guard abs(value.translation.width) > abs(value.translation.height) * 0.6 else { return }
                if !isDragging {
                    isDragging = true
                    latch.reset(isPast: isOpen)
                }
                dragTranslation = value.translation.width
                latch.update(isPast: progress(width: width) > 0.5)
            }
            .onEnded { value in
                isDragging = false
                // Velocity-aware: a fast flick wins over distance travelled.
                let predicted = (isOpen ? width : 0) + value.predictedEndTranslation.width
                let shouldOpen = predicted > width * 0.5
                dragTranslation = 0
                setOpen(shouldOpen)
            }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(MotionSystem.resolved(MotionSystem.sidebar, reduceMotion: reduceMotion)) {
            isOpen = open
        }
        latch.reset(isPast: open)
    }
}
