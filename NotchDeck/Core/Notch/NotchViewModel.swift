import Foundation
import Observation

/// State and intents exposed to the SwiftUI notch surface.
///
/// The view reads from this model and reports user intent through it; it never
/// changes presentation state directly. `NotchController` owns and updates it.
@MainActor
@Observable
final class NotchViewModel {
    private(set) var state: NotchPresentationState = .idle
    private(set) var geometry: NotchGeometry?

    /// Height of the expanded content as last measured by the view. The surface sizes itself to fit.
    private(set) var expandedContentHeight: CGFloat?

    /// The command-center tab the user picked. Reset to the overview whenever the notch collapses.
    var selectedSection: CommandCenterSection = .overview

    /// The drag currently hovering the shelf, if any.
    private(set) var shelfDrag: ShelfDrag?

    @ObservationIgnored let engine: ActivityEngine
    /// Called when measured content changes the size of the current surface.
    @ObservationIgnored var onLayoutChange: (() -> Void)?
    @ObservationIgnored var onClick: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?

    init(engine: ActivityEngine) {
        self.engine = engine
    }

    var resolution: ActivityResolution {
        engine.resolution
    }

    var metrics: NotchMetrics? {
        geometry.map {
            NotchLayout.metrics(for: state, notchSize: $0.notchSize, expandedContentHeight: expandedContentHeight)
        }
    }

    func updateExpandedContentHeight(_ height: CGFloat) {
        // Ignore sub-point jitter so layout passes don't resize the panel repeatedly.
        if let current = expandedContentHeight, abs(current - height) < 1 { return }
        expandedContentHeight = height
        if state == .expanded {
            onLayoutChange?()
        }
    }

    func update(state: NotchPresentationState, geometry: NotchGeometry?) {
        if self.state != state {
            if state != .expanded { selectedSection = .overview }
            if state != .shelf { shelfDrag = nil }
            self.state = state
        }
        if self.geometry != geometry { self.geometry = geometry }
    }

    func click() {
        onClick?()
    }

    func perform(_ action: ActivityAction, on activity: NotchActivity) {
        engine.perform(action, on: activity.key)
    }

    func perform(actionID: ActivityAction.ID, on activity: NotchActivity) {
        engine.perform(actionID: actionID, on: activity.key)
    }

    func updateShelfDrag(_ drag: ShelfDrag?) {
        if shelfDrag != drag { shelfDrag = drag }
    }

    func openSettings() {
        onOpenSettings?()
    }
}

/// A drag hovering the shelf: where it is (in the notch view's top-left coordinate space)
/// and a short, user-facing description of what is being dragged.
struct ShelfDrag: Equatable {
    var location: CGPoint
    var itemDescription: String
}
