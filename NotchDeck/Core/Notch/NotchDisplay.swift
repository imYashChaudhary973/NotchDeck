import Foundation

/// Which activities are on screen for a given notch state. Reported to the engine so providers
/// can stop work nobody can see (for example, CPU sampling while the command center is closed).
enum NotchDisplay {
    static func displayedKeys(
        state: NotchPresentationState,
        resolution: ActivityResolution,
        selectedSection: CommandCenterSection
    ) -> Set<ActivityKey> {
        switch state {
        case .idle, .shelf:
            return []
        case .liveActivity, .peek:
            return resolution.primary.map { [$0.key] } ?? []
        case .expanded:
            let layout = CommandCenterLayout.make(resolution: resolution, selected: selectedSection)
            return Set(([layout.featured].compactMap { $0 } + layout.widgets).map(\.key))
        }
    }
}

/// Converts scroll-wheel input over the notch into normalized steps.
enum NotchScroll {
    /// One step per mouse-wheel notch; trackpads produce about one step per 16 points of travel.
    static let pointsPerStep: Double = 16

    /// - Parameters:
    ///   - deltaY: `NSEvent.scrollingDeltaY`.
    ///   - isPrecise: `hasPreciseScrollingDeltas` (trackpads, Magic Mouse).
    ///   - isInverted: `isDirectionInvertedFromDevice` (natural scrolling).
    /// - Returns: Steps where positive means the fingers or wheel moved up.
    static func steps(deltaY: Double, isPrecise: Bool, isInverted: Bool) -> Double {
        let physical = isInverted ? -deltaY : deltaY
        return isPrecise ? physical / pointsPerStep : physical
    }
}
