import Foundation

/// How strongly an activity competes for the notch.
///
/// The named levels are the base values from the engineering plan. Intermediate
/// values are allowed (for example, a timer with one minute left might use 35).
struct ActivityPriority: RawRepresentable, Hashable, Comparable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Background context; shown only when nothing else is relevant.
    static let ambient = ActivityPriority(rawValue: 10)
    /// Ongoing but low urgency, such as music playing.
    static let passive = ActivityPriority(rawValue: 20)
    /// Something the user is engaged with, such as a running timer.
    static let active = ActivityPriority(rawValue: 30)
    /// Relevant now and soon stale, such as a meeting about to start.
    static let timeSensitive = ActivityPriority(rawValue: 40)
    /// The user needs to act, such as an agent waiting for input.
    static let attentionRequired = ActivityPriority(rawValue: 50)
    /// Rare; must be seen immediately.
    static let critical = ActivityPriority(rawValue: 60)

    static func < (lhs: ActivityPriority, rhs: ActivityPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether the activity should proactively reveal itself (auto-peek) when it becomes primary.
    var requestsAttention: Bool {
        self >= .attentionRequired
    }

    /// Human-readable name of the nearest named level at or below this priority.
    var levelName: String {
        switch rawValue {
        case ..<20: "Ambient"
        case 20..<30: "Passive"
        case 30..<40: "Active"
        case 40..<50: "Time Sensitive"
        case 50..<60: "Attention Required"
        default: "Critical"
        }
    }
}
