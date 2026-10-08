import Foundation

/// The resolver's output: what deserves the notch now, and what is waiting.
struct ActivityResolution: Equatable, Sendable {
    /// The activity that owns the notch, if any.
    var primary: NotchActivity?
    /// Other live activities, most important first.
    var queued: [NotchActivity]

    static let empty = ActivityResolution(primary: nil, queued: [])

    var all: [NotchActivity] {
        (primary.map { [$0] } ?? []) + queued
    }
}

/// Decides which activity owns the notch.
///
/// Rules:
/// 1. Expired activities are ignored.
/// 2. Higher priority wins.
/// 3. Among equal priorities, the currently displayed activity keeps the notch (no flapping).
/// 4. Otherwise, the most recently published activity wins.
/// 5. Only `.notch` activities can be primary; `.commandCenter` activities are always queued.
///
/// Because the store keeps interrupted activities, removing a higher-priority activity
/// automatically restores the one it interrupted.
struct ActivityResolver: Sendable {
    func resolve(_ stored: [StoredActivity], current: ActivityKey?, now: Date) -> ActivityResolution {
        let ranked = stored
            .filter { !$0.activity.isExpired(at: now) }
            .sorted { lhs, rhs in
                if lhs.activity.priority != rhs.activity.priority {
                    return lhs.activity.priority > rhs.activity.priority
                }
                return lhs.sequence > rhs.sequence
            }
            .map(\.activity)

        let eligible = ranked.filter { $0.placement == .notch }
        guard var primary = eligible.first else {
            return ActivityResolution(primary: nil, queued: ranked)
        }

        if let current,
           let incumbent = eligible.first(where: { $0.key == current }),
           incumbent.priority == primary.priority {
            primary = incumbent
        }

        let queued = ranked.filter { $0.key != primary.key }
        return ActivityResolution(primary: primary, queued: queued)
    }
}
