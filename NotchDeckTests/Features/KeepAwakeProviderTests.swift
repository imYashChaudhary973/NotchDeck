import Foundation
import Testing
@testable import NotchDeck

@MainActor
final class FakePowerAssertion: PowerAssertionControlling {
    private(set) var isHeld = false
    private(set) var lastTimeout: TimeInterval?
    private(set) var acquireCount = 0

    func acquire(reason: String, timeout: TimeInterval?) -> Bool {
        isHeld = true
        lastTimeout = timeout
        acquireCount += 1
        return true
    }

    func release() {
        isHeld = false
    }
}

@MainActor
struct KeepAwakeProviderTests {
    let clock = TestClock()
    let assertion = FakePowerAssertion()
    let suiteName = "NotchDeckTests.KeepAwake.\(UUID().uuidString)"
    let defaults: UserDefaults
    let engine: ActivityEngine
    let key = ActivityKey(source: ActivitySource(rawValue: "keepAwake"), id: KeepAwakeProvider.activityID)

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        let clock = clock
        engine = ActivityEngine(now: { clock.now }, schedulesExpiry: false)
    }

    private func makeProvider() -> KeepAwakeProvider {
        let clock = clock
        return KeepAwakeProvider(assertion: assertion, defaults: defaults, now: { clock.now }, schedulesEnd: false)
    }

    @Test func offByDefaultAndOnlyListedInTheCommandCenter() {
        engine.register(makeProvider())

        #expect(!assertion.isHeld)
        #expect(engine.resolution.primary == nil)
        let activity = engine.activity(for: key)
        #expect(activity?.placement == .commandCenter)
        #expect(activity?.presentation.content == .toggle(ToggleContent(isOn: false, actionID: KeepAwakeProvider.ActionID.toggle, stateText: "Off")))
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func timedSessionHoldsAnAssertionWithASystemTimeout() {
        let provider = makeProvider()
        engine.register(provider)

        engine.perform(actionID: KeepAwakeDuration.oneHour.actionID, on: key)

        #expect(assertion.isHeld)
        #expect(assertion.lastTimeout == 3600)
        #expect(provider.session == .until(clock.now.addingTimeInterval(3600)))
        #expect(engine.resolution.primary?.key == key)
        #expect(engine.resolution.primary?.priority == .ambient)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func togglingTurnsOnIndefinitelyThenOff() {
        let provider = makeProvider()
        engine.register(provider)

        engine.perform(actionID: KeepAwakeProvider.ActionID.toggle, on: key)
        #expect(provider.session == .indefinite)
        #expect(assertion.isHeld)
        #expect(assertion.lastTimeout == nil)

        engine.perform(actionID: KeepAwakeProvider.ActionID.toggle, on: key)
        #expect(provider.session == .off)
        #expect(!assertion.isHeld)
        #expect(engine.resolution.primary == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func timedSessionEndsAndReleasesTheAssertion() {
        let provider = makeProvider()
        engine.register(provider)
        provider.turnOn(for: .thirtyMinutes)

        clock.advance(by: 29 * 60)
        provider.endIfDue()
        #expect(assertion.isHeld)

        clock.advance(by: 60)
        provider.endIfDue()
        #expect(!assertion.isHeld)
        #expect(provider.session == .off)
        #expect(engine.resolution.primary == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func activeSessionIsRestoredAfterRelaunchWithTheRemainingTime() {
        let first = makeProvider()
        engine.register(first)
        first.turnOn(for: .twoHours)
        engine.unregister(first.source)
        #expect(!assertion.isHeld)

        clock.advance(by: 3600)
        let second = makeProvider()
        engine.register(second)

        #expect(assertion.isHeld)
        #expect(assertion.lastTimeout == 3600)
        #expect(engine.resolution.primary?.key == key)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func expiredSessionIsNotRestored() {
        let first = makeProvider()
        engine.register(first)
        first.turnOn(for: .thirtyMinutes)
        engine.unregister(first.source)

        clock.advance(by: 3600)
        let second = makeProvider()
        engine.register(second)

        #expect(!assertion.isHeld)
        #expect(second.session == .off)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func turnOffIsSaved() {
        let provider = makeProvider()
        engine.register(provider)
        provider.turnOn(for: .indefinite)
        provider.turnOff()

        #expect(KeepAwakeProvider.load(from: defaults) == .off)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func onChangeIsCalledForEverySessionChange() {
        let provider = makeProvider()
        var changes = 0
        provider.onChange = { changes += 1 }
        engine.register(provider)
        provider.turnOn(for: .oneHour)
        provider.turnOff()

        #expect(changes == 3)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
