import Foundation

/// The notch's presentation levels, from least to most intrusive.
enum NotchPresentationState: String, Sendable, CaseIterable {
    /// The notch looks like a notch.
    case idle
    /// A compact extension beside the notch showing the primary activity.
    case liveActivity
    /// A brief, slightly expanded view (hover or attention).
    case peek
    /// The full panel, opened deliberately.
    case expanded
    /// A drop target for dragged content.
    case shelf

    /// Whether interaction outside the notch should dismiss this state.
    var isTransient: Bool {
        switch self {
        case .idle, .liveActivity: false
        case .peek, .expanded, .shelf: true
        }
    }
}

/// Inputs to the state machine. Produced by the notch controller from user interaction and engine output.
enum NotchEvent: Equatable, Sendable {
    /// Whether the engine currently has a primary activity.
    case activityAvailabilityChanged(hasActivity: Bool)
    /// A primary activity that requests attention appeared or escalated.
    case attentionRequested
    case pointerEntered
    case pointerExited
    case clicked
    case clickedOutside
    /// Programmatic or keyboard dismissal back to the resting state.
    case dismiss
    /// The auto-dismiss delay for an attention peek elapsed.
    case peekTimedOut
    case dragEntered
    case dragExited
    case dropCompleted
}

/// The formal model of notch presentation. A pure value type with no side effects.
///
/// The controller feeds it events and reacts to state changes (window frame,
/// event monitors, timers). All transition rules live here so they can be unit tested.
struct NotchStateMachine: Sendable {
    struct Configuration: Equatable, Sendable {
        /// Hovering the notch opens Peek.
        var peeksOnHover = true
        /// Moving the pointer out of the expanded notch collapses it.
        var collapsesWhenPointerExits = true
        /// Activities that request attention open Peek automatically.
        var peeksForAttention = true
    }

    private(set) var state: NotchPresentationState = .idle
    private(set) var hasActivity = false
    private(set) var isPointerInside = false
    /// `true` when the current Peek was opened by an attention request rather than by hover.
    private(set) var isAttentionPeek = false

    var configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// The state the notch returns to when nothing transient is open.
    var restingState: NotchPresentationState {
        hasActivity ? .liveActivity : .idle
    }

    /// Applies an event. Returns `true` if `state` changed.
    @discardableResult
    mutating func handle(_ event: NotchEvent) -> Bool {
        let previous = state

        switch event {
        case .activityAvailabilityChanged(let available):
            hasActivity = available
            if !state.isTransient || (state == .peek && isAttentionPeek && !available) {
                rest()
            }

        case .attentionRequested:
            if configuration.peeksForAttention, !state.isTransient {
                state = .peek
                isAttentionPeek = true
            }

        case .pointerEntered:
            isPointerInside = true
            if state == .peek {
                // The user is now engaged; keep the peek open until they leave.
                isAttentionPeek = false
            } else if configuration.peeksOnHover, !state.isTransient {
                state = .peek
                isAttentionPeek = false
            }

        case .pointerExited:
            isPointerInside = false
            switch state {
            case .peek where !isAttentionPeek:
                rest()
            case .expanded where configuration.collapsesWhenPointerExits:
                rest()
            default:
                break
            }

        case .clicked:
            if state != .expanded, state != .shelf {
                state = .expanded
                isAttentionPeek = false
            }

        case .clickedOutside, .dismiss:
            if state.isTransient {
                rest()
            }

        case .peekTimedOut:
            if state == .peek, isAttentionPeek, !isPointerInside {
                rest()
            }

        case .dragEntered:
            state = .shelf
            isAttentionPeek = false

        case .dragExited, .dropCompleted:
            if state == .shelf {
                rest()
            }
        }

        return state != previous
    }

    private mutating func rest() {
        state = restingState
        isAttentionPeek = false
    }
}
