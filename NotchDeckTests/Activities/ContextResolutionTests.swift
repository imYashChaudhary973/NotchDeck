import Foundation
import Testing
@testable import NotchDeck

/// Competing real providers resolve predictably: a meeting interrupts music as it approaches, takes
/// the notch with an attention peek as it starts, and music returns once the meeting is over.
@MainActor
struct ContextResolutionTests {
    let clock = TestClock()
    let engine: ActivityEngine
    let music = FakeMediaProvider(id: "music")
    let calendarStore = FakeCalendarStore()
    let musicKey = ActivityKey(source: ActivitySource(rawValue: "music"), id: MusicProvider.activityID)
    var meetingStart: Date { Date(timeIntervalSinceReferenceDate: 1_000 + 3600) }
    var meetingKey: ActivityKey { ActivityKey(source: ActivitySource(rawValue: "calendar"), id: CalendarProvider.meetingIDPrefix + "review") }

    init() {
        let clock = clock
        engine = ActivityEngine(now: { clock.now }, schedulesExpiry: false)
    }

    private func makeCalendar() -> CalendarProvider {
        CalendarProvider(store: calendarStore, workspace: FakeWorkspace(), now: { [clock] in clock.now }, schedulesWakeUps: false)
    }

    private func setUp() -> CalendarProvider {
        music.nowPlaying = MusicProviderTests.track("Midnight City")
        calendarStore.allEvents = [CalendarEvent(
            id: "review", title: "Design Review", start: meetingStart, end: meetingStart.addingTimeInterval(1800),
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )]
        let calendar = makeCalendar()
        engine.register(MusicProvider(players: [music], workspace: FakeWorkspace(), now: { [clock] in clock.now }))
        engine.register(calendar)
        return calendar
    }

    private func move(_ calendar: CalendarProvider, toStartOffset offset: TimeInterval) {
        clock.now = meetingStart.addingTimeInterval(offset)
        calendar.advance()
        engine.expireActivities()
    }

    @Test func meetingInterruptsMusicAndMusicReturns() {
        let calendar = setUp()
        var attentionRequests = 0
        engine.onResolutionChange = { old, new in
            if let primary = new.primary, primary.priority.requestsAttention,
               old.primary?.key != primary.key || old.primary?.priority.requestsAttention != true {
                attentionRequests += 1
            }
        }

        // Music playing (20), meeting an hour away: music owns the notch.
        #expect(engine.resolution.primary?.key == musicKey)

        // 15 minutes before (30): the meeting interrupts; music waits in the queue.
        move(calendar, toStartOffset: -15 * 60)
        #expect(engine.resolution.primary?.key == meetingKey)
        #expect(engine.resolution.queued.contains { $0.key == musicKey })

        // 3 minutes (40), then starting (50): still the meeting, now requesting attention once.
        move(calendar, toStartOffset: -3 * 60)
        #expect(engine.resolution.primary?.priority == .timeSensitive)
        move(calendar, toStartOffset: 0)
        #expect(engine.resolution.primary?.priority == .attentionRequired)
        #expect(attentionRequests == 1)

        // After the "Starting now" grace period, music returns automatically.
        move(calendar, toStartOffset: 5 * 60)
        #expect(engine.resolution.primary?.key == musicKey)
    }

    @Test func joiningTheMeetingRestoresMusicImmediately() {
        let calendar = setUp()
        move(calendar, toStartOffset: 0)
        #expect(engine.resolution.primary?.key == meetingKey)

        engine.perform(actionID: CalendarProvider.ActionID.join, on: meetingKey)

        #expect(engine.resolution.primary?.key == musicKey)
    }

    @Test func engineExpiryAloneRestoresMusicIfTheCalendarNeverWakes() {
        let calendar = setUp()
        move(calendar, toStartOffset: 0)
        #expect(engine.resolution.primary?.key == meetingKey)

        // The provider doesn't run (e.g. the app was busy); the activity's own expiry still applies.
        clock.now = meetingStart.addingTimeInterval(5 * 60)
        engine.expireActivities()

        #expect(engine.resolution.primary?.key == musicKey)
    }

    @Test func pausedMusicDoesNotComeBackToTheNotch() {
        let calendar = setUp()
        move(calendar, toStartOffset: -10 * 60)
        music.update { $0.nowPlaying?.state = .paused }

        move(calendar, toStartOffset: 5 * 60)

        #expect(engine.resolution.primary == nil)
        #expect(engine.activity(for: musicKey)?.placement == .commandCenter)
    }

    // MARK: Developer agents

    private func makeDeveloper() -> (DeveloperActivityProvider, FakeDeveloperEventSource) {
        let events = FakeDeveloperEventSource()
        let developer = DeveloperActivityProvider(source: events, workspace: FakeDeveloperWorkspace(),
                                                  now: { [clock] in clock.now }, schedulesWakeUps: false)
        engine.register(developer)
        return (developer, events)
    }

    private func isAgent(_ activity: NotchActivity?) -> Bool {
        activity?.source == ActivitySource(rawValue: "developer")
    }

    @Test func aWorkingAgentInterruptsMusicAndMusicReturnsAfterTheFinish() {
        _ = setUp()
        let (developer, events) = makeDeveloper()

        events.send(.agent(.working, project: "Rove"))
        #expect(isAgent(engine.resolution.primary))
        #expect(engine.resolution.queued.contains { $0.key == musicKey })

        events.send(.agent(.completed))
        #expect(engine.resolution.primary?.title == "Rove finished")

        clock.advance(by: DeveloperActivityRules.completedNotchDuration)
        developer.advance()
        #expect(engine.resolution.primary?.key == musicKey)
    }

    @Test func aMeetingFifteenMinutesAwayBeatsAWorkingAgent() {
        let calendar = setUp()
        let (_, events) = makeDeveloper()
        move(calendar, toStartOffset: -20 * 60)
        events.send(.agent(.working, project: "Rove"))
        #expect(isAgent(engine.resolution.primary))

        // Upcoming (30) outranks an ordinary working agent (25).
        move(calendar, toStartOffset: -15 * 60)
        #expect(engine.resolution.primary?.key == meetingKey)
        #expect(engine.resolution.queued.contains { isAgent($0) })

        // A working agent publishing updates doesn't take it back.
        events.send(.agent(.runningCommand, message: "swift test"))
        #expect(engine.resolution.primary?.key == meetingKey)
    }

    @Test func anAgentNeedingPermissionBeatsAMeetingFiveMinutesAway() {
        let calendar = setUp()
        let (_, events) = makeDeveloper()
        move(calendar, toStartOffset: -5 * 60)
        events.send(.agent(.working, project: "Rove"))
        #expect(engine.resolution.primary?.key == meetingKey)
        #expect(engine.resolution.primary?.priority == .timeSensitive)

        events.send(.agent(.needsPermission, message: "Claude needs your permission to use Bash"))
        #expect(isAgent(engine.resolution.primary))
        #expect(engine.resolution.primary?.priority == .attentionRequired)

        // Approved: the agent works on (25) and the meeting (40) has the notch again.
        events.send(.agent(.working))
        #expect(engine.resolution.primary?.key == meetingKey)
    }

    @Test func endingAnAgentThatNeedsYouRestoresMusic() {
        _ = setUp()
        let (_, events) = makeDeveloper()
        events.send(.agent(.needsInput, project: "Rove"))
        #expect(isAgent(engine.resolution.primary))

        events.send(.ending())

        #expect(engine.resolution.primary?.key == musicKey)
    }

    @Test func aRunningTimerKeepsTheNotchAgainstAnEqualPriorityMeeting() {
        let calendar = setUp()
        engine.publish(makeActivity("timer", source: .testA, priority: .active, kind: .timer))
        #expect(engine.resolution.primary?.id == "timer")

        // Upcoming meeting (30) ties with the running timer (30): the incumbent keeps the notch.
        move(calendar, toStartOffset: -10 * 60)
        #expect(engine.resolution.primary?.id == "timer")

        // Within 5 minutes (40) the meeting wins.
        move(calendar, toStartOffset: -4 * 60)
        #expect(engine.resolution.primary?.key == meetingKey)
    }
}
