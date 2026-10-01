import Foundation
import Testing
@testable import NotchDeck

struct ActivityStoreTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func upsertInsertsAndUpdatesInPlace() {
        var store = ActivityStore()
        store.upsert(makeActivity("a", title: "First"))
        store.upsert(makeActivity("b"))
        store.upsert(makeActivity("a", title: "Updated"))

        #expect(store.count == 2)
        #expect(store.activity(for: ActivityKey(source: .testA, id: "a"))?.title == "Updated")
    }

    @Test func updatingKeepsOriginalInsertionOrder() {
        var store = ActivityStore()
        store.upsert(makeActivity("a"))
        store.upsert(makeActivity("b"))
        store.upsert(makeActivity("a", title: "Updated"))

        #expect(store.all.map(\.activity.id) == ["a", "b"])
    }

    @Test func sameIDFromDifferentSourcesAreDistinct() {
        var store = ActivityStore()
        store.upsert(makeActivity("x", source: .testA))
        store.upsert(makeActivity("x", source: .testB))

        #expect(store.count == 2)
    }

    @Test func removeAllFromSourceOnlyAffectsThatSource() {
        var store = ActivityStore()
        store.upsert(makeActivity("a1", source: .testA))
        store.upsert(makeActivity("a2", source: .testA))
        store.upsert(makeActivity("b1", source: .testB))

        let removed = store.removeAll(from: .testA)

        #expect(removed.count == 2)
        #expect(store.all.map(\.activity.id) == ["b1"])
    }

    @Test func removeExpiredRemovesOnlyExpiredActivities() {
        var store = ActivityStore()
        store.upsert(makeActivity("past", expiresAt: now.addingTimeInterval(-1)))
        store.upsert(makeActivity("exact", expiresAt: now))
        store.upsert(makeActivity("future", expiresAt: now.addingTimeInterval(10)))
        store.upsert(makeActivity("forever"))

        let removed = store.removeExpired(at: now)

        #expect(Set(removed.map(\.id)) == ["past", "exact"])
        #expect(Set(store.all.map(\.activity.id)) == ["future", "forever"])
    }

    @Test func nextExpiryIsTheEarliestExpiry() {
        var store = ActivityStore()
        #expect(store.nextExpiry == nil)

        store.upsert(makeActivity("late", expiresAt: now.addingTimeInterval(60)))
        store.upsert(makeActivity("soon", expiresAt: now.addingTimeInterval(5)))
        store.upsert(makeActivity("forever"))

        #expect(store.nextExpiry == now.addingTimeInterval(5))
    }

    @Test func progressIsClampedToUnitRange() {
        let over = NotchActivity(id: "p", source: .testA, kind: .generic, priority: .active, title: "p", progress: 1.5, presentation: ActivityPresentation(symbolName: "circle"))
        let under = NotchActivity(id: "p", source: .testA, kind: .generic, priority: .active, title: "p", progress: -0.5, presentation: ActivityPresentation(symbolName: "circle"))

        #expect(over.progress == 1)
        #expect(under.progress == 0)
    }
}
