import SwiftUI

/// Root of the notch panel. Draws the notch surface for the current state, top-centered
/// in the panel, and animates between states.
struct NotchRootView: View {
    let model: NotchViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let metrics = model.metrics, let geometry = model.geometry {
                NotchSurface(model: model, metrics: metrics, notchSize: geometry.notchSize)
                    .frame(width: metrics.outerSize.width, height: metrics.outerSize.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(stateAnimation, value: model.state)
        .animation(stateAnimation, value: model.resolution.primary?.key)
        .environment(\.colorScheme, .dark)
    }

    /// Springs retarget mid-flight, so rapid state changes stay smooth and interruptible.
    private var stateAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.8)
    }
}

/// The black notch shape plus the content for the current state.
private struct NotchSurface: View {
    let model: NotchViewModel
    let metrics: NotchMetrics
    let notchSize: CGSize

    var body: some View {
        let shape = NotchShape(topCornerRadius: metrics.topCornerRadius, bottomCornerRadius: metrics.bottomCornerRadius)

        ZStack(alignment: .top) {
            shape.fill(.black)
            content
                .padding(.horizontal, metrics.topCornerRadius)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
        .clipShape(shape)
        .contentShape(shape)
        .foregroundStyle(.white)
        .onTapGesture { model.click() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("NotchDeck")
    }

    @ViewBuilder
    private var content: some View {
        let primary = model.resolution.primary
        switch model.state {
        case .idle:
            Color.clear
        case .liveActivity:
            if let primary {
                CompactActivityView(activity: primary, notchSize: notchSize)
                    .id(primary.key)
            }
        case .peek:
            PeekView(activity: primary, notchSize: notchSize)
        case .expanded:
            ExpandedView(model: model, notchSize: notchSize)
        case .shelf:
            ShelfDropView(notchSize: notchSize)
        }
    }
}
