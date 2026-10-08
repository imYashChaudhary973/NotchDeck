import Foundation
import Testing
@testable import NotchDeck

@MainActor
struct TimerProviderTests {
    let clock = TestClock()
    let suiteName = "NotchDeckTests.Timers.\(UUID().uuidString)"
    let defaults: UserDefaults
    let engine: ActivityEngine

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        let clock = clock
        engine = ActivityEngine(now: { clock.now }, schedulesExpiry: false)
    }

    private func makeProvider() -> TimerProvider {
        let clock = clock
        return TimerProvider(defaults: defaults, now: { clock.now }, schedulesTransitions: false)
    }

    private func key(_ id: UUID) -> ActivityKey {
        ActivityKey(source: ActivitySource(rawValue: "timer"), id: TimerProvider.activityID(for: id))
    }

    private var presetsKey: ActivityKey {
        ActivityKey(source: ActivitySource(rawValue: "timer"), id: TimerProvider.presetsActivityID)
    }

    @Test func publishesOnlyThePresetsRowWhenIdle() {
        engine.register(makeProvider())

        #expect(engine.resolution.primary == nil)
        #expect(engine.resolution.all.map(\.key) == [presetsKey])
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func startingATimerPublishesALiveActivityWithACountdown() {
        let provider = makeProvider()
        engine.register(provider)

        let id = provider.startTimer(duration: 300)

        let primary = engine.resolution.primary
        #expect(primary?.key == key(id))
        #expect(primary?.kind == .timer)
        #expect(primary?.priority == .active)
        #expect(primary?.presentation.compactAccessory == .countdown(to: clock.now.addingTimeInterval(300)))
        #expect(primary?.actions.map(\.id) == [TimerProvider.ActionID.pause, TimerProvider.ActionID.addMinute, TimerProvider.ActionID.cancel])
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func onlyTheMostRelevantTimerCompetesForTheNotch() {
        let provider = makeProvider()
        engine.register(provider)
        let long = provider.startTimer(duration: 3_600)
        let short = provider.startTimer(duration: 300)

        #expect(engine.resolution.primary?.key == key(short))
        #expect(engine.activity(for: key(long))?.placement == .commandCenter)

        engine.perform(actionID: TimerProvider.ActionID.cancel, on: key(short))

        #expect(engine.resolution.primary?.key == key(long))
        #expect(engine.activity(for: key(short)) == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func pauseAndResumeActionsAreRoutedThroughTheEngine() {
        let provider = makeProvider()
        engine.register(provider)
        let id = provider.startTimer(duration: 300)
        clock.advance(by: 60)

        engine.perform(actionID: TimerProvider.ActionID.pause, on: key(id))
        let paused = engine.activity(for: key(id))
        #expect(paused?.priority == .passive)
        #expect(paused?.presentation.compactAccessory == .text("4:00"))
        #expect(paused?.actions.map(\.id) == [TimerProvider.ActionID.resume, TimerProvider.ActionID.cancel])

        clock.advance(by: 600)
        engine.perform(actionID: TimerProvider.ActionID.resume, on: key(id))
        #expect(engine.activity(for: key(id))?.presentation.compactAccessory == .countdown(to: clock.now.addingTimeInterval(240)))
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func priorityEscalatesAsTheTimerApproachesZeroAndFinishes() {
        let provider = makeProvider()
        var finished: [UUID] = []
        provider.onFinish = { finished.append($0.id) }
        engine.register(provider)
        let id = provider.startTimer(duration: 120)

        clock.advance(by: 60)
        provider.advance()
        #expect(engine.activity(for: key(id))?.priority.rawValue == 35)

        clock.advance(by: 50)
        provider.advance()
        #expect(engine.activity(for: key(id))?.priority == .timeSensitive)
        #expect(engine.activity(for: key(id))?.presentation.accent == .red)

        clock.advance(by: 10)
        provider.advance()
        let done = engine.activity(for: key(id))
        #expect(done?.priority == .attentionRequired)
        #expect(done?.presentation.symbolName == "bell.fill")
        #expect(done?.expiresAt == clock.now.addingTimeInterval(TimerRules.finishedAlertDuration))
        #expect(finished == [id])

        clock.advance(by: TimerRules.finishedAlertDuration)
        provider.advance()
        #expect(engine.activity(for: key(id)) == nil)
        #expect(finished == [id])
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func presetAndCustomActionsStartTimers() {
        let provider = makeProvider()
        var customRequested = false
        provider.onRequestCustomDuration = { customRequested = true }
        engine.register(provider)

        engine.perform(actionID: TimerProvider.ActionID.preset(600), on: presetsKey)
        engine.perform(actionID: TimerProvider.ActionID.custom, on: presetsKey)

        #expect(provider.collection.timers.map(\.duration) == [600])
        #expect(customRequested)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func timersAreRestoredAfterRelaunch() {
        let first = makeProvider()
        engine.register(first)
        let id = first.startTimer(duration: 600, label: "Tea")
        engine.unregister(first.source)
        #expect(engine.resolution.primary == nil)

        clock.advance(by: 100)
        let second = makeProvider()
        engine.register(second)

        #expect(engine.resolution.primary?.key == key(id))
        #expect(engine.resolution.primary?.title == "Tea")
        #expect(second.collection.timer(id)?.remaining(at: clock.now) == 500)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func cancelAllClearsSavedTimers() {
        let provider = makeProvider()
        engine.register(provider)
        provider.startTimer(duration: 600)

        provider.cancelAll()

        #expect(engine.resolution.primary == nil)
        #expect(TimerProvider.load(from: defaults).isEmpty)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func activityIDsRoundTrip() {
        let id = UUID()
        #expect(TimerProvider.timerID(from: TimerProvider.activityID(for: id)) == id)
        #expect(TimerProvider.timerID(from: TimerProvider.presetsActivityID) == nil)
    }
}
