import Foundation
import Testing
@testable import NotchDeck

@MainActor
final class FakeCalendarStore: CalendarStore {
    var authorization: CalendarAuthorization
    /// What the user answers when asked.
    var answer: CalendarAuthorization = .fullAccess
    var allEvents: [CalendarEvent] = []
    var calendarList: [CalendarInfo] = [CalendarInfo(id: "work", title: "Work", sourceTitle: "iCloud", accent: .blue)]
    private(set) var accessRequests = 0
    private(set) var queries: [(start: Date, end: Date, excluded: Set<String>)] = []
    private(set) var isObserving = false
    private var onChange: (@MainActor () -> Void)?

    init(authorization: CalendarAuthorization = .fullAccess) {
        self.authorization = authorization
    }

    func requestAccess() async -> CalendarAuthorization {
        accessRequests += 1
        authorization = answer
        return answer
    }

    func calendars() -> [CalendarInfo] { calendarList }

    func events(from start: Date, to end: Date, excludingCalendars excluded: Set<String>) -> [CalendarEvent] {
        queries.append((start, end, excluded))
        return allEvents
            .filter { $0.end > start && $0.start < end && !excluded.contains($0.calendarID) }
            .sorted { $0.start < $1.start }
    }

    func startObserving(onChange: @escaping @MainActor () -> Void) {
        isObserving = true
        self.onChange = onChange
    }

    func stopObserving() {
        isObserving = false
        onChange = nil
    }

    /// Simulates EventKit reporting a change.
    func change(_ update: (FakeCalendarStore) -> Void) {
        update(self)
        onChange?()
    }
}

@MainActor
struct CalendarProviderTests {
    let engine = ActivityEngine(now: { Date(timeIntervalSinceReferenceDate: 0) }, schedulesExpiry: false)
    let clock = TestClock()
    let source = ActivitySource(rawValue: "calendar")

    var meetingStart: Date { Date(timeIntervalSinceReferenceDate: 1_000 + 3600) }

    func meeting(_ id: String = "standup", in offset: TimeInterval? = nil, duration: TimeInterval = 1800,
                 url: URL? = URL(string: "https://zoom.us/j/1"), calendar: String = "work", allDay: Bool = false) -> CalendarEvent {
        let start = offset.map { clock.now.addingTimeInterval($0) } ?? meetingStart
        return CalendarEvent(id: id, title: id.capitalized, start: start, end: start.addingTimeInterval(duration),
                             isAllDay: allDay, calendarID: calendar, meetingURL: url)
    }

    func makeProvider(
        _ store: FakeCalendarStore,
        configuration: CalendarProvider.Configuration = .init(),
        workspace: FakeWorkspace = FakeWorkspace()
    ) -> CalendarProvider {
        CalendarProvider(store: store, configuration: { configuration }, workspace: workspace,
                         now: { [clock] in clock.now }, schedulesWakeUps: false)
    }

    func key(_ id: String) -> ActivityKey { ActivityKey(source: source, id: id) }
    func meetingKey(_ eventID: String) -> ActivityKey { key(CalendarProvider.meetingIDPrefix + eventID) }

    /// Moves the clock to `offset` seconds from the meeting start and lets the provider catch up.
    func move(_ provider: CalendarProvider, toStartOffset offset: TimeInterval) {
        clock.now = meetingStart.addingTimeInterval(offset)
        provider.advance()
    }

    // MARK: Permission

    @Test func startingNeverAsksForAccess() throws {
        let store = FakeCalendarStore(authorization: .notDetermined)
        engine.register(makeProvider(store))

        #expect(store.accessRequests == 0)
        #expect(store.queries.isEmpty)
        let access = try #require(engine.activity(for: key(CalendarProvider.accessActivityID)))
        #expect(access.placement == .commandCenter)
        #expect(access.actions.map(\.id) == [CalendarProvider.ActionID.allowAccess])
    }

    @Test func allowingAccessLoadsEvents() async throws {
        let store = FakeCalendarStore(authorization: .notDetermined)
        store.allEvents = [meeting()]
        let provider = makeProvider(store)
        engine.register(provider)

        engine.perform(actionID: CalendarProvider.ActionID.allowAccess, on: key(CalendarProvider.accessActivityID))
        for _ in 0..<20 where store.queries.isEmpty { await Task.yield() }

        #expect(store.accessRequests == 1)
        #expect(provider.authorization == .fullAccess)
        #expect(provider.calendars.map(\.id) == ["work"])
        #expect(engine.activity(for: key(CalendarProvider.accessActivityID)) == nil)
        #expect(engine.activity(for: key(CalendarProvider.scheduleActivityID)) != nil)
    }

    @Test(arguments: [CalendarAuthorization.denied, .restricted, .writeOnly])
    func withoutReadAccessOnlyTheSettingsPromptIsShown(_ authorization: CalendarAuthorization) throws {
        let workspace = FakeWorkspace()
        let store = FakeCalendarStore(authorization: authorization)
        store.allEvents = [meeting(in: 60)]
        let provider = makeProvider(store, workspace: workspace)
        engine.register(provider)

        #expect(store.queries.isEmpty)
        #expect(engine.resolution.primary == nil)
        #expect(engine.resolution.queued.map(\.id) == [CalendarProvider.accessActivityID])

        // Asking again doesn't show a prompt the system won't show; it just re-checks.
        provider.requestAccess()
        #expect(store.accessRequests == 0)

        engine.perform(actionID: CalendarProvider.ActionID.openSettings, on: key(CalendarProvider.accessActivityID))
        #expect(workspace.opened == [CalendarProvider.privacySettingsURL])
    }

    @Test func declinedPromptKeepsTheFeatureQuiet() async {
        let store = FakeCalendarStore(authorization: .notDetermined)
        store.answer = .denied
        let provider = makeProvider(store)
        engine.register(provider)

        provider.requestAccess()
        for _ in 0..<20 where provider.authorization == .notDetermined { await Task.yield() }

        #expect(provider.authorization == .denied)
        #expect(engine.activity(for: key(CalendarProvider.accessActivityID))?.actions.map(\.id) == [CalendarProvider.ActionID.openSettings])
        #expect(engine.resolution.primary == nil)
    }

    // MARK: Meetings

    @Test func meetingEscalatesAsItApproachesThenLeaves() throws {
        let store = FakeCalendarStore()
        store.allEvents = [meeting()]
        let provider = makeProvider(store)
        engine.register(provider)
        let key = meetingKey("standup")

        // An hour away: only in the schedule.
        #expect(engine.resolution.primary == nil)
        #expect(engine.activity(for: self.key(CalendarProvider.scheduleActivityID))?.subtitle?.hasSuffix("Standup") == true)

        move(provider, toStartOffset: -12 * 60)
        var activity = try #require(engine.resolution.primary)
        #expect(activity.key == key)
        #expect(activity.priority == .active)
        #expect(activity.presentation.compactAccessory == .text("12m"))
        #expect(activity.presentation.statusText == "In 12 min")
        #expect(activity.actions.map(\.id) == [CalendarProvider.ActionID.join, CalendarProvider.ActionID.dismiss])
        #expect(activity.presentation.symbolName == "video.fill")

        move(provider, toStartOffset: -4 * 60)
        activity = try #require(engine.resolution.primary)
        #expect(activity.priority == .timeSensitive)
        #expect(activity.presentation.compactAccessory == .text("4m"))

        move(provider, toStartOffset: 0)
        activity = try #require(engine.resolution.primary)
        #expect(activity.priority == .attentionRequired)
        #expect(activity.presentation.statusText == "Starting now")
        #expect(activity.expiresAt == meetingStart.addingTimeInterval(5 * 60))

        move(provider, toStartOffset: 5 * 60)
        #expect(engine.resolution.primary == nil)
        let entries = scheduleEntries()
        #expect(entries.first?.isNow == true)

        // Over: gone from the schedule too.
        move(provider, toStartOffset: 30 * 60)
        #expect(engine.activity(for: self.key(CalendarProvider.scheduleActivityID)) == nil)
    }

    @Test func theSoonestMeetingOwnsTheNotch() throws {
        let store = FakeCalendarStore()
        store.allEvents = [meeting("later", in: 10 * 60), meeting("sooner", in: 3 * 60)]
        engine.register(makeProvider(store))

        #expect(engine.resolution.primary?.key == meetingKey("sooner"))
        #expect(engine.activity(for: meetingKey("later")) == nil)
        #expect(scheduleEntries().map(\.id) == ["sooner", "later"])
    }

    @Test func allDayEventsAreListedButNeverOnTheNotch() {
        let store = FakeCalendarStore()
        store.allEvents = [meeting("offsite", in: -3600, duration: 86_400, allDay: true), meeting("standup", in: 2 * 3600)]
        engine.register(makeProvider(store))

        #expect(engine.resolution.primary == nil)
        let entries = scheduleEntries()
        #expect(entries.map(\.id) == ["offsite", "standup"])
        #expect(entries.first?.isAllDay == true)
        #expect(entries.first?.joinActionID == nil)
    }

    @Test func dismissingReturnsTheNotch() {
        let store = FakeCalendarStore()
        store.allEvents = [meeting(in: 60)]
        engine.register(makeProvider(store))
        #expect(engine.resolution.primary?.key == meetingKey("standup"))

        engine.perform(actionID: CalendarProvider.ActionID.dismiss, on: meetingKey("standup"))

        #expect(engine.resolution.primary == nil)
        #expect(scheduleEntries().map(\.id) == ["standup"])
    }

    @Test func joiningOpensTheLinkAndLeavesTheNotch() {
        let workspace = FakeWorkspace()
        let store = FakeCalendarStore()
        store.allEvents = [meeting(in: 30)]
        engine.register(makeProvider(store, workspace: workspace))

        engine.perform(actionID: CalendarProvider.ActionID.join, on: meetingKey("standup"))

        #expect(workspace.opened == [URL(string: "https://zoom.us/j/1")!])
        #expect(engine.resolution.primary == nil)
    }

    @Test func joiningFromTheSchedule() {
        let workspace = FakeWorkspace()
        let store = FakeCalendarStore()
        store.allEvents = [meeting(in: 2 * 3600)]
        engine.register(makeProvider(store, workspace: workspace))
        let join = scheduleEntries().first?.joinActionID

        #expect(join == CalendarProvider.ActionID.joinPrefix + "standup")
        engine.perform(actionID: join ?? "", on: key(CalendarProvider.scheduleActivityID))

        #expect(workspace.opened == [URL(string: "https://zoom.us/j/1")!])
    }

    @Test func meetingsWithoutALinkHaveNoJoinButton() throws {
        let store = FakeCalendarStore()
        store.allEvents = [meeting(in: 60, url: nil)]
        engine.register(makeProvider(store))

        let activity = try #require(engine.resolution.primary)
        #expect(activity.actions.map(\.id) == [CalendarProvider.ActionID.dismiss])
        #expect(activity.presentation.symbolName == "calendar")
        #expect(scheduleEntries().first?.joinActionID == nil)
    }

    // MARK: Refresh scheduling

    @Test func queriesOnlyOnStartChangesAndTheRefetchInterval() {
        let store = FakeCalendarStore()
        store.allEvents = [meeting()]
        let provider = makeProvider(store, configuration: .init(lookAhead: 3 * 3600))
        engine.register(provider)
        #expect(store.queries.count == 1)
        #expect(store.queries.first?.end == clock.now.addingTimeInterval(3 * 3600 + CalendarProvider.refetchInterval))

        // Rule boundaries are evaluated from the cache.
        move(provider, toStartOffset: -10 * 60)
        move(provider, toStartOffset: 0)
        #expect(store.queries.count == 1)

        store.change { $0.allEvents = [] }
        #expect(store.queries.count == 2)
        #expect(engine.resolution.primary == nil)

        clock.advance(by: CalendarProvider.refetchInterval)
        provider.advance()
        #expect(store.queries.count == 3)
    }

    @Test func excludedCalendarsAreNotQueried() {
        let store = FakeCalendarStore()
        store.allEvents = [meeting(in: 60, calendar: "personal")]
        engine.register(makeProvider(store, configuration: .init(excludedCalendarIDs: ["personal"])))

        #expect(store.queries.first?.excluded == ["personal"])
        #expect(engine.resolution.primary == nil)
        #expect(engine.activity(for: key(CalendarProvider.scheduleActivityID)) == nil)
    }

    @Test func nextChangeIsTheNearestBoundaryOrMinuteTick() {
        let rules = CalendarRules.standard
        let event = meeting()

        // An hour out: the next thing is entering the notch, 15 minutes before.
        #expect(CalendarProvider.nextChange(events: [event], dismissed: [], rules: rules, after: clock.now)
            == meetingStart.addingTimeInterval(-15 * 60))
        // On the notch: the countdown's next minute.
        let onNotch = meetingStart.addingTimeInterval(-12 * 60)
        #expect(CalendarProvider.nextChange(events: [event], dismissed: [], rules: rules, after: onNotch)
            == meetingStart.addingTimeInterval(-11 * 60))
        // Dismissed: no minute ticks, just the next boundary.
        #expect(CalendarProvider.nextChange(events: [event], dismissed: ["standup"], rules: rules, after: onNotch)
            == meetingStart.addingTimeInterval(-5 * 60))
        // After it ends, nothing.
        #expect(CalendarProvider.nextChange(events: [event], dismissed: [], rules: rules, after: event.end) == nil)
    }

    @Test func stoppingStopsObserving() {
        let store = FakeCalendarStore()
        store.allEvents = [meeting(in: 60)]
        let provider = makeProvider(store)
        engine.register(provider)
        #expect(store.isObserving)

        engine.unregister(provider.source)

        #expect(!store.isObserving)
        #expect(engine.resolution.all.isEmpty)
    }

    // MARK: Helpers

    private func scheduleEntries() -> [ScheduleContent.Entry] {
        guard case .schedule(let schedule) = engine.activity(for: key(CalendarProvider.scheduleActivityID))?.presentation.content else {
            return []
        }
        return schedule.entries
    }
}
