import Foundation
import Observation

/// Meetings from the user's calendars (EventKit): the next meeting on the notch as it approaches,
/// a "Starting now" alert with a Join button, and the upcoming schedule in the command center.
///
/// Calendar access is requested only when the user turns the feature on (or presses Allow);
/// starting the provider never shows the system prompt.
///
/// Event-driven: EventKit is queried when the provider starts, when the store, clock or day
/// changes, after wake and every `refetchInterval` (to see further ahead). In between, the provider
/// wakes only at the next rule boundary of a cached event, plus once a minute while a meeting
/// countdown is on the notch.
@MainActor
@Observable
final class CalendarProvider: ActivityProvider {
    struct Configuration: Equatable, Sendable {
        /// How far ahead the schedule looks.
        var lookAhead: TimeInterval = 12 * 3600
        var rules: CalendarRules = .standard
        var excludedCalendarIDs: Set<String> = []
    }

    let source = ActivitySource(rawValue: "calendar")
    static let scheduleActivityID = "schedule"
    static let accessActivityID = "access"
    static let meetingIDPrefix = "meeting-"
    /// Orders the schedule above Volume and the metric rows in the command center.
    static let schedulePriority = ActivityPriority(rawValue: 17)
    static let maxScheduleEntries = 6
    /// Events are fetched this far beyond the look-ahead, so EventKit is queried about four times a day.
    static let refetchInterval: TimeInterval = 6 * 3600
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    enum ActionID {
        static let join = "join"
        static let dismiss = "dismiss"
        static let allowAccess = "allowAccess"
        static let openSettings = "openSettings"
        static let joinPrefix = "join-"
    }

    /// Current permission, for Settings.
    private(set) var authorization: CalendarAuthorization
    /// Calendars available once access is granted, for Settings.
    private(set) var calendars: [CalendarInfo] = []

    @ObservationIgnored private(set) var events: [CalendarEvent] = []
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var dismissed: Set<String> = []
    @ObservationIgnored private var publishedIDs: Set<NotchActivity.ID> = []
    @ObservationIgnored private var publisher: ActivityPublisher?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private let store: any CalendarStore
    @ObservationIgnored private let configuration: () -> Configuration
    @ObservationIgnored private let workspace: any WorkspaceOpening
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let schedulesWakeUps: Bool

    /// - Parameters:
    ///   - now: Clock, injectable for tests.
    ///   - schedulesWakeUps: When `false`, time only moves on when `advance()` is called.
    init(
        store: any CalendarStore,
        configuration: @escaping () -> Configuration = { Configuration() },
        workspace: any WorkspaceOpening = SystemWorkspace(),
        now: @escaping () -> Date = { .now },
        schedulesWakeUps: Bool = true
    ) {
        self.store = store
        self.configuration = configuration
        self.workspace = workspace
        self.now = now
        self.schedulesWakeUps = schedulesWakeUps
        authorization = store.authorization
    }

    // MARK: ActivityProvider

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
        store.startObserving { [weak self] in self?.reload() }
        reload()
    }

    func stop() {
        store.stopObserving()
        wakeTask?.cancel()
        wakeTask = nil
        publisher = nil
        publishedIDs.removeAll()
        events = []
        fetchedAt = nil
    }

    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
        switch actionID {
        case ActionID.allowAccess:
            requestAccess()
        case ActionID.openSettings:
            workspace.open(Self.privacySettingsURL)
        case ActionID.join:
            guard let event = event(forActivityID: activityID) else { return }
            join(event)
        case ActionID.dismiss:
            guard let event = event(forActivityID: activityID) else { return }
            dismissed.insert(event.id)
            evaluate()
        default:
            if actionID.hasPrefix(ActionID.joinPrefix),
               let event = events.first(where: { $0.id == actionID.dropFirst(ActionID.joinPrefix.count) }) {
                join(event)
            }
        }
    }

    // MARK: Commands

    /// Shows the system calendar prompt if the user hasn't answered it yet, then loads events.
    func requestAccess() {
        guard store.authorization == .notDetermined else {
            reload()
            return
        }
        Task {
            authorization = await store.requestAccess()
            reload()
        }
    }

    /// Re-reads permission and the calendar list only (for Settings, even while the feature is off).
    func refreshAuthorization() {
        authorization = store.authorization
        calendars = authorization.canReadEvents ? store.calendars() : []
    }

    /// Re-reads permission, calendars and events (after a store or settings change).
    func reload() {
        authorization = store.authorization
        let date = now()
        if authorization.canReadEvents {
            let config = configuration()
            calendars = store.calendars()
            events = store.events(
                from: date,
                to: date.addingTimeInterval(config.lookAhead + Self.refetchInterval),
                excludingCalendars: config.excludedCalendarIDs
            )
            fetchedAt = date
        } else {
            calendars = []
            events = []
            fetchedAt = nil
        }
        dismissed.formIntersection(events.map(\.id))
        evaluate()
    }

    /// Applies changes due by now. Called by the scheduled wake-up, or directly in tests.
    func advance() {
        if let fetchedAt, now() >= fetchedAt.addingTimeInterval(Self.refetchInterval) {
            reload()
        } else {
            evaluate()
        }
    }

    private func join(_ event: CalendarEvent) {
        guard let url = event.meetingURL else { return }
        workspace.open(url)
        // Joined: the meeting leaves the notch, and whatever it interrupted returns.
        dismissed.insert(event.id)
        evaluate()
    }

    private func event(forActivityID activityID: NotchActivity.ID) -> CalendarEvent? {
        guard activityID.hasPrefix(Self.meetingIDPrefix) else { return nil }
        let id = activityID.dropFirst(Self.meetingIDPrefix.count)
        return events.first { $0.id == id }
    }

    // MARK: Publishing

    private func evaluate() {
        guard let publisher else { return }
        let date = now()
        let config = configuration()
        let activities = Self.activities(
            authorization: authorization,
            events: events,
            dismissed: dismissed,
            configuration: config,
            now: date,
            source: source
        )
        let ids = Set(activities.map(\.id))
        for stale in publishedIDs.subtracting(ids) {
            publisher.withdraw(id: stale)
        }
        activities.forEach(publisher.publish)
        publishedIDs = ids
        scheduleWakeUp(after: date, configuration: config)
    }

    private func scheduleWakeUp(after date: Date, configuration config: Configuration) {
        wakeTask?.cancel()
        wakeTask = nil
        guard schedulesWakeUps, publisher != nil else { return }
        var next = Self.nextChange(events: events, dismissed: dismissed, rules: config.rules, after: date)
        if let fetchedAt {
            let refetch = fetchedAt.addingTimeInterval(Self.refetchInterval)
            next = min(next ?? refetch, refetch)
        }
        guard let next else { return }
        let delay = max(next.timeIntervalSince(date), 0)
        wakeTask = Task { [weak self] in
            // Continuous clock: keeps counting across sleep.
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(1), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    // MARK: Rules

    /// The event that owns the notch at `date`: the soonest one a rule applies to.
    static func notchEvent(events: [CalendarEvent], dismissed: Set<String>, rules: CalendarRules, at date: Date) -> CalendarEvent? {
        events
            .filter { !dismissed.contains($0.id) && rules.rule(for: $0, at: date) != nil }
            .min { $0.start < $1.start }
    }

    /// The next date anything shown changes: a rule boundary, a start or end in the schedule, or
    /// the next minute of the countdown on the notch.
    static func nextChange(events: [CalendarEvent], dismissed: Set<String>, rules: CalendarRules, after date: Date) -> Date? {
        var candidates = events.flatMap { rules.boundaries(for: $0) + [$0.start, $0.end] }
        if let shown = notchEvent(events: events, dismissed: dismissed, rules: rules, at: date),
           let tick = MeetingCountdown.nextChange(start: shown.start, after: date) {
            candidates.append(tick)
        }
        return candidates.filter { $0 > date }.min()
    }

    // MARK: Activities

    static func activities(
        authorization: CalendarAuthorization,
        events: [CalendarEvent],
        dismissed: Set<String>,
        configuration: Configuration,
        now: Date,
        source: ActivitySource
    ) -> [NotchActivity] {
        guard authorization.canReadEvents else {
            return [accessActivity(for: authorization, source: source)]
        }
        var activities: [NotchActivity] = []
        if let event = notchEvent(events: events, dismissed: dismissed, rules: configuration.rules, at: now),
           let rule = configuration.rules.rule(for: event, at: now) {
            activities.append(meetingActivity(for: event, rule: rule, rules: configuration.rules, now: now, source: source))
        }
        if let schedule = scheduleActivity(events: events, lookAhead: configuration.lookAhead, now: now, source: source) {
            activities.append(schedule)
        }
        return activities
    }

    static func meetingActivity(for event: CalendarEvent, rule: MeetingRule, rules: CalendarRules, now: Date, source: ActivitySource) -> NotchActivity {
        let started = event.start <= now
        let timeRange = "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
        let relative = started ? "Started" : "in \(MeetingCountdown.minutesUntilStart(event.start, at: now)) min"
        var actions: [ActivityAction] = []
        if event.meetingURL != nil {
            actions.append(ActivityAction(id: ActionID.join, title: "Join", systemImage: "video.fill"))
        }
        actions.append(ActivityAction(id: ActionID.dismiss, title: "Dismiss", systemImage: "xmark"))

        return NotchActivity(
            id: meetingIDPrefix + event.id,
            source: source,
            kind: .meeting,
            priority: rule.priority,
            title: event.title,
            subtitle: "\(timeRange) · \(relative)",
            startedAt: event.start,
            // Leaves the notch on its own even if no wake-up runs (e.g. the provider was stopped).
            expiresAt: rules.notchEnd(for: event),
            presentation: ActivityPresentation(
                symbolName: event.meetingURL == nil ? "calendar" : "video.fill",
                accent: event.accent == .neutral ? .blue : event.accent,
                compactAccessory: .text(MeetingCountdown.compactText(start: event.start, at: now)),
                statusText: MeetingCountdown.statusText(start: event.start, at: now)
            ),
            actions: actions
        )
    }

    /// The upcoming schedule: events in progress or starting within the look-ahead. Nil when empty.
    static func scheduleActivity(events: [CalendarEvent], lookAhead: TimeInterval, now: Date, source: ActivitySource) -> NotchActivity? {
        let horizon = now.addingTimeInterval(lookAhead)
        let upcoming = events
            .filter { $0.end > now && $0.start < horizon }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.start < rhs.start
            }
        guard !upcoming.isEmpty else { return nil }

        let entries = upcoming.prefix(maxScheduleEntries).map { event in
            ScheduleContent.Entry(
                id: event.id,
                title: event.title,
                start: event.start,
                end: event.end,
                isAllDay: event.isAllDay,
                accent: event.accent,
                isNow: event.isInProgress(at: now),
                joinActionID: event.meetingURL == nil || event.isAllDay ? nil : ActionID.joinPrefix + event.id
            )
        }
        let next = upcoming.first { !$0.isAllDay && $0.start > now }
        let current = upcoming.first { !$0.isAllDay && $0.isInProgress(at: now) }
        let subtitle: String = if let next {
            "\(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)"
        } else if let current {
            "Now: \(current.title)"
        } else {
            "All-day events"
        }

        return NotchActivity(
            id: scheduleActivityID,
            source: source,
            kind: .meeting,
            priority: schedulePriority,
            placement: .commandCenter,
            title: "Up Next",
            subtitle: subtitle,
            presentation: ActivityPresentation(
                symbolName: "calendar",
                accent: .blue,
                content: .schedule(ScheduleContent(entries: Array(entries)))
            )
        )
    }

    static func accessActivity(for authorization: CalendarAuthorization, source: ActivitySource) -> NotchActivity {
        let (subtitle, action): (String, ActivityAction) = switch authorization {
        case .notDetermined:
            ("Allow calendar access to see upcoming meetings here.",
             ActivityAction(id: ActionID.allowAccess, title: "Allow Access…", systemImage: "lock.open"))
        case .writeOnly:
            ("NotchDeck can only add events. Allow full access to see meetings.",
             ActivityAction(id: ActionID.openSettings, title: "Open Settings…", systemImage: "gearshape"))
        case .restricted:
            ("Calendar access is restricted on this Mac.",
             ActivityAction(id: ActionID.openSettings, title: "Open Settings…", systemImage: "gearshape"))
        case .denied, .fullAccess:
            ("Calendar access is off. Turn it on in Privacy & Security.",
             ActivityAction(id: ActionID.openSettings, title: "Open Settings…", systemImage: "gearshape"))
        }
        return NotchActivity(
            id: accessActivityID,
            source: source,
            kind: .meeting,
            priority: schedulePriority,
            placement: .commandCenter,
            title: "Calendar",
            subtitle: subtitle,
            presentation: ActivityPresentation(symbolName: "calendar.badge.exclamationmark", accent: .blue),
            actions: [action]
        )
    }
}
