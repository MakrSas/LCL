import SwiftUI

/// An interactive, finger-following drawer that slides **over** the content.
///
/// `NavigationSplitView` collapses to a stack on iPhone and gives no drag-to-reveal drawer,
/// so this is a custom container (docs/PRODUCT_SPEC.md §6).
///
/// ## Why the content does not move
///
/// It used to. Three attempts at making that smooth failed, and the reason is Liquid Glass:
/// glass samples whatever is behind it, and the composer and toolbar are glass *inside* the
/// chat. Translating that content forced every glass surface to re-sample its backdrop on
/// every frame — so the more correctly we used the system's glass controls, the worse the
/// drawer stuttered.
///
/// Now only the sidebar moves: a plain `VStack` of a few rows with an opaque background, which
/// is a cheap translation. The content stays put and merely dims, so nothing behind the glass
/// changes and nothing needs re-sampling.
///
/// Kept from before: 1:1 finger tracking with no animation during the drag, velocity-aware
/// settle via `predictedEndTranslation`, an interruptible spring, a latched threshold haptic,
/// and a real button for VoiceOver.
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
                // The sidebar sits UNDERNEATH, revealed as the chat slides off it.
                sidebar
                    .frame(width: width)
                    .background(Palette.canvasRaised, ignoresSafeAreaEdges: .vertical)
                    // Slight parallax so it reads as depth rather than a sheet sliding in.
                    .offset(x: reduceMotion ? 0 : -width * 0.18 * (1 - progress))
                    .opacity(reduceMotion ? (progress > 0.5 ? 1 : 0) : progress)
                    .accessibilityHidden(progress < 0.9)

                content
                    .disabled(isOpen)
                    .overlay {
                        if progress > 0 {
                            Color.black
                                .opacity(0.35 * progress)
                                .ignoresSafeArea()
                                .onTapGesture { setOpen(false) }
                                .gesture(drag(width: width))
                                .accessibilityLabel("Close sidebar")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    // Offset and a corner radius, but no scale and no shadow. Those two were
                    // the expensive parts: a shadow re-rasterises the whole surface each
                    // frame, and scaling resamples the entire subtree.
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: Radius.sidebarPeel * progress,
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

                // THE BUG, fixed: these two must change inside ONE animation block.
                // Resetting dragTranslation outside it snapped `progress` back to its base
                // instantly, and only then did the spring run — which read as the animation
                // playing a second time after releasing the finger. Together they interpolate
                // once, continuously, from wherever the finger left off.
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
