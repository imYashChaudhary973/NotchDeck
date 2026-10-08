import Foundation

/// How strongly a meeting competes for the notch some time before it starts.
struct MeetingRule: Equatable, Sendable {
    var name: String
    /// The rule applies from this long before the start.
    var leadTime: TimeInterval
    var priority: ActivityPriority
}

/// When a meeting takes the notch and how urgent it is. Pure, so every boundary is unit tested.
///
/// Defaults (from the engineering plan): beyond 15 minutes a meeting is only listed in the
/// schedule; within 15 minutes it is Active (30), so it interrupts music (20); within 5 minutes
/// Time Sensitive (40); from one minute before the start Attention Required (50), which peeks.
/// It stays as "Starting now" for a grace period after the start, then leaves the notch, and
/// whatever it interrupted returns.
struct CalendarRules: Equatable, Sendable {
    static let soonLeadTime: TimeInterval = 5 * 60
    static let startingLeadTime: TimeInterval = 60
    static let defaultNotchLeadTime: TimeInterval = 15 * 60
    static let defaultStartingGracePeriod: TimeInterval = 5 * 60

    /// Every rule, longest lead time first.
    private(set) var rules: [MeetingRule]
    /// How long after the start the meeting stays on the notch (capped at its end).
    var startingGracePeriod: TimeInterval

    init(rules: [MeetingRule], startingGracePeriod: TimeInterval = defaultStartingGracePeriod) {
        self.rules = rules.sorted { $0.leadTime > $1.leadTime }
        self.startingGracePeriod = max(startingGracePeriod, 0)
    }

    /// The default rules, with the meeting first shown on the notch `notchLeadTime` before it starts.
    init(notchLeadTime: TimeInterval = defaultNotchLeadTime, startingGracePeriod: TimeInterval = defaultStartingGracePeriod) {
        let lead = max(notchLeadTime, Self.startingLeadTime)
        var rules: [MeetingRule] = []
        if lead > Self.soonLeadTime {
            rules.append(MeetingRule(name: "Upcoming", leadTime: lead, priority: .active))
        }
        if lead > Self.startingLeadTime {
            rules.append(MeetingRule(name: "Soon", leadTime: min(lead, Self.soonLeadTime), priority: .timeSensitive))
        }
        rules.append(MeetingRule(name: "Starting now", leadTime: Self.startingLeadTime, priority: .attentionRequired))
        self.init(rules: rules, startingGracePeriod: startingGracePeriod)
    }

    static let standard = CalendarRules()

    /// How long before the start the event first reaches the notch.
    var notchLeadTime: TimeInterval {
        rules.first?.leadTime ?? 0
    }

    /// When the event leaves the notch.
    func notchEnd(for event: CalendarEvent) -> Date {
        min(event.start.addingTimeInterval(startingGracePeriod), event.end)
    }

    /// The rule in effect for `event` at `date`; nil when it is not (or no longer) notch-worthy.
    /// All-day events never take the notch.
    func rule(for event: CalendarEvent, at date: Date) -> MeetingRule? {
        guard !event.isAllDay, date < notchEnd(for: event) else { return nil }
        let untilStart = event.start.timeIntervalSince(date)
        // The applicable rule is the one with the shortest lead time that still covers the gap.
        return rules.last { untilStart <= $0.leadTime }
    }

    /// Dates at which `rule(for:at:)` changes for `event`.
    func boundaries(for event: CalendarEvent) -> [Date] {
        guard !event.isAllDay else { return [] }
        return rules.map { event.start.addingTimeInterval(-$0.leadTime) } + [event.start, notchEnd(for: event)]
    }
}

/// The relative time shown for a meeting on the notch, at minute precision.
enum MeetingCountdown {
    /// Whole minutes until the start, rounded up; 0 once it has started.
    static func minutesUntilStart(_ start: Date, at date: Date) -> Int {
        let seconds = start.timeIntervalSince(date)
        return seconds <= 0 ? 0 : Int((seconds / 60).rounded(.up))
    }

    /// "12m" or "Now", for the compact ear.
    static func compactText(start: Date, at date: Date) -> String {
        let minutes = minutesUntilStart(start, at: date)
        return minutes == 0 ? "Now" : "\(minutes)m"
    }

    /// "In 12 min" or "Starting now".
    static func statusText(start: Date, at date: Date) -> String {
        let minutes = minutesUntilStart(start, at: date)
        return minutes == 0 ? "Starting now" : "In \(minutes) min"
    }

    /// The next date the minute text changes, while the start is ahead.
    static func nextChange(start: Date, after date: Date) -> Date? {
        let minutes = minutesUntilStart(start, at: date)
        guard minutes > 0 else { return nil }
        return start.addingTimeInterval(-Double(minutes - 1) * 60)
    }
}
