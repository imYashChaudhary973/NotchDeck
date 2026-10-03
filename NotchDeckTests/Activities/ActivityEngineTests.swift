import Foundation
import Testing
@testable import NotchDeck

@MainActor
final class RecordingProvider: ActivityProvider {
    let source: ActivitySource
    private(set) var publisher: ActivityPublisher?
    private(set) var performed: [(action: String, activity: String)] = []
    private(set) var stopCount = 0

    init(source: ActivitySource = .testA) {
        self.source = source
    }

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
    }

    func stop() {
        stopCount += 1
    }

    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
        performed.append((actionID, activityID))
    }
}

@MainActor
struct ActivityEngineTests {
    let clock = TestClock()
    let engine: ActivityEngine

    init() {
        let clock = clock
        engine = ActivityEngine(now: { clock.now }, schedulesExpiry: false)
    }

    @Test func providerPublishesThroughItsPublisher() {
        let provider = RecordingProvider()
        engine.register(provider)

        provider.publisher?.publish(makeActivity("music"))

        #expect(engine.resolution.primary?.id == "music")
    }

    @Test func publisherCanWithdrawItsActivities() {
        let provider = RecordingProvider()
        engine.register(provider)
        provider.publisher?.publish(makeActivity("a"))
        provider.publisher?.publish(makeActivity("b"))

        provider.publisher?.withdraw(id: "b")
        #expect(engine.resolution.all.map(\.id) == ["a"])

        provider.publisher?.withdrawAll()
        #expect(engine.resolution == .empty)
    }

    @Test func unregisteringStopsProviderAndWithdrawsItsActivities() {
        let a = RecordingProvider(source: .testA)
        let b = RecordingProvider(source: .testB)
        engine.register(a)
        engine.register(b)
        a.publisher?.publish(makeActivity("a", source: .testA))
        b.publisher?.publish(makeActivity("b", source: .testB))

        engine.unregister(.testA)

        #expect(a.stopCount == 1)
        #expect(engine.resolution.all.map(\.id) == ["b"])
    }

    @Test func actionsAreRoutedToTheOwningProvider() {
        let a = RecordingProvider(source: .testA)
        let b = RecordingProvider(source: .testB)
        engine.register(a)
        engine.register(b)

        engine.perform(ActivityAction(id: "pause", title: "Pause"), on: ActivityKey(source: .testB, id: "music"))

        #expect(a.performed.isEmpty)
        #expect(b.performed.map(\.action) == ["pause"])
        #expect(b.performed.map(\.activity) == ["music"])
    }

    @Test func expiryRemovesActivityAndRestoresPrevious() {
        engine.publish(makeActivity("music", priority: .passive))
        engine.publish(makeActivity("meeting", priority: .timeSensitive, expiresAt: clock.now.addingTimeInterval(30)))
        #expect(engine.resolution.primary?.id == "meeting")

        clock.advance(by: 29)
        engine.expireActivities()
        #expect(engine.resolution.primary?.id == "meeting")

        clock.advance(by: 1)
        engine.expireActivities()
        #expect(engine.resolution.primary?.id == "music")
        #expect(engine.activity(for: ActivityKey(source: .testA, id: "meeting")) == nil)
    }

    @Test func resolutionChangeCallbackReportsOldAndNew() {
        var changes: [(String?, String?)] = []
        engine.onResolutionChange = { old, new in
            changes.append((old.primary?.id, new.primary?.id))
        }

        engine.publish(makeActivity("music", priority: .passive))
        engine.publish(makeActivity("agent", priority: .attentionRequired))
        engine.withdraw(ActivityKey(source: .testA, id: "agent"))

        #expect(changes.map(\.0) == [nil, "music", "agent"])
        #expect(changes.map(\.1) == ["music", "agent", "music"])
    }

    @Test func unchangedResolutionDoesNotNotify() {
        var count = 0
        engine.publish(makeActivity("music"))
        engine.onResolutionChange = { _, _ in count += 1 }

        engine.publish(makeActivity("music"))
        engine.withdraw(ActivityKey(source: .testA, id: "missing"))

        #expect(count == 0)
    }

    @Test func scheduledExpiryFiresWithoutPolling() async throws {
        let liveEngine = ActivityEngine()
        liveEngine.publish(makeActivity("music", priority: .passive))
        liveEngine.publish(makeActivity("toast", priority: .active, expiresAt: .now.addingTimeInterval(0.2)))
        #expect(liveEngine.resolution.primary?.id == "toast")

        try await Task.sleep(for: .milliseconds(800))

        #expect(liveEngine.resolution.primary?.id == "music")
    }
}
