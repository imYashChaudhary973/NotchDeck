import Foundation

/// An activity together with the order in which it was first published.
struct StoredActivity: Equatable, Sendable {
    var activity: NotchActivity
    /// Monotonic insertion order. Preserved when an activity is updated in place.
    let sequence: Int
}

/// The single source of truth for all live activities.
///
/// A plain value type with no timers or side effects; the `ActivityEngine` owns scheduling.
struct ActivityStore: Sendable {
    private var entries: [ActivityKey: StoredActivity] = [:]
    private var nextSequence = 0

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    /// All stored activities, oldest first.
    var all: [StoredActivity] {
        entries.values.sorted { $0.sequence < $1.sequence }
    }

    func activity(for key: ActivityKey) -> NotchActivity? {
        entries[key]?.activity
    }

    /// Inserts a new activity or replaces an existing one with the same key.
    mutating func upsert(_ activity: NotchActivity) {
        if let existing = entries[activity.key] {
            entries[activity.key] = StoredActivity(activity: activity, sequence: existing.sequence)
        } else {
            entries[activity.key] = StoredActivity(activity: activity, sequence: nextSequence)
            nextSequence += 1
        }
    }

    @discardableResult
    mutating func remove(_ key: ActivityKey) -> NotchActivity? {
        entries.removeValue(forKey: key)?.activity
    }

    @discardableResult
    mutating func removeAll(from source: ActivitySource) -> [NotchActivity] {
        let keys = entries.keys.filter { $0.source == source }
        return keys.compactMap { entries.removeValue(forKey: $0)?.activity }
    }

    /// Removes every activity whose expiry is at or before `date`.
    @discardableResult
    mutating func removeExpired(at date: Date) -> [NotchActivity] {
        let keys = entries.values.filter { $0.activity.isExpired(at: date) }.map(\.activity.key)
        return keys.compactMap { entries.removeValue(forKey: $0)?.activity }
    }

    /// The earliest upcoming expiry date, used to schedule a single wake-up instead of polling.
    var nextExpiry: Date? {
        entries.values.compactMap(\.activity.expiresAt).min()
    }
}
