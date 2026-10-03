import Foundation
import Testing
@testable import NotchDeck

struct ActivityResolverTests {
    let resolver = ActivityResolver()
    let now = Date(timeIntervalSinceReferenceDate: 1_000)

    private func resolve(_ store: ActivityStore, current: ActivityKey? = nil) -> ActivityResolution {
        resolver.resolve(store.all, current: current, now: now)
    }

    @Test func emptyStoreResolvesToNothing() {
        #expect(resolve(ActivityStore()) == .empty)
    }

    @Test func highestPriorityWins() {
        var store = ActivityStore()
        store.upsert(makeActivity("music", priority: .passive))
        store.upsert(makeActivity("agent", priority: .attentionRequired))
        store.upsert(makeActivity("timer", priority: .active))

        let resolution = resolve(store)

        #expect(resolution.primary?.id == "agent")
        #expect(resolution.queued.map(\.id) == ["timer", "music"])
    }

    @Test func intermediatePrioritiesOrderBetweenLevels() {
        var store = ActivityStore()
        store.upsert(makeActivity("active", priority: .active))
        store.upsert(makeActivity("timerOneMinute", priority: ActivityPriority(rawValue: 35)))
        store.upsert(makeActivity("timeSensitive", priority: .timeSensitive))

        #expect(resolve(store).all.map(\.id) == ["timeSensitive", "timerOneMinute", "active"])
    }

    @Test func newestWinsAmongEqualPrioritiesWithoutIncumbent() {
        var store = ActivityStore()
        store.upsert(makeActivity("older", priority: .passive))
        store.upsert(makeActivity("newer", priority: .passive))

        #expect(resolve(store).primary?.id == "newer")
    }

    @Test func incumbentKeepsNotchAgainstEqualPriority() {
        var store = ActivityStore()
        store.upsert(makeActivity("music", priority: .passive))
        let current = resolve(store).primary?.key

        store.upsert(makeActivity("clipboard", priority: .passive))
        let resolution = resolve(store, current: current)

        #expect(resolution.primary?.id == "music")
        #expect(resolution.queued.map(\.id) == ["clipboard"])
    }

    @Test func higherPriorityInterruptsIncumbent() {
        var store = ActivityStore()
        store.upsert(makeActivity("music", priority: .passive))
        let current = resolve(store).primary?.key

        store.upsert(makeActivity("meeting", priority: .timeSensitive))

        #expect(resolve(store, current: current).primary?.id == "meeting")
    }

    @Test func interruptedActivityIsRestoredWhenInterrupterIsRemoved() {
        var store = ActivityStore()
        store.upsert(makeActivity("music", priority: .passive))
        store.upsert(makeActivity("meeting", priority: .timeSensitive))
        let current = resolve(store).primary?.key
        #expect(current?.id == "meeting")

        store.remove(ActivityKey(source: .testA, id: "meeting"))

        #expect(resolve(store, current: current).primary?.id == "music")
    }

    @Test func expiredActivitiesAreIgnored() {
        var store = ActivityStore()
        store.upsert(makeActivity("music", priority: .passive))
        store.upsert(makeActivity("stale", priority: .critical, expiresAt: now.addingTimeInterval(-1)))

        let resolution = resolve(store)

        #expect(resolution.primary?.id == "music")
        #expect(resolution.queued.isEmpty)
    }

    @Test func priorityChangeOfIncumbentIsRespected() {
        var store = ActivityStore()
        store.upsert(makeActivity("timer", priority: .active))
        store.upsert(makeActivity("transfer", priority: .active))
        // "transfer" is newer, so it is shown first.
        let current = resolve(store).primary?.key
        #expect(current?.id == "transfer")

        // The timer escalates as it nears zero and takes over.
        store.upsert(makeActivity("timer", priority: .timeSensitive))

        #expect(resolve(store, current: current).primary?.id == "timer")
    }

    @Test func staleIncumbentKeyFallsBackToRanking() {
        var store = ActivityStore()
        store.upsert(makeActivity("a", priority: .passive))
        store.upsert(makeActivity("b", priority: .passive))

        let resolution = resolve(store, current: ActivityKey(source: .testA, id: "gone"))

        #expect(resolution.primary?.id == "b")
    }
}
