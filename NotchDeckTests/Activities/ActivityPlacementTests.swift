import Foundation
import Testing
@testable import NotchDeck

struct ActivityPlacementTests {
    let resolver = ActivityResolver()
    let now = Date(timeIntervalSinceReferenceDate: 1_000)

    private func resolve(_ activities: [NotchActivity], current: ActivityKey? = nil) -> ActivityResolution {
        var store = ActivityStore()
        activities.forEach { store.upsert($0) }
        return resolver.resolve(store.all, current: current, now: now)
    }

    @Test func commandCenterActivitiesNeverBecomePrimary() {
        let resolution = resolve([
            makeActivity("quickActions", priority: .critical, placement: .commandCenter),
            makeActivity("timer", priority: .active),
        ])

        #expect(resolution.primary?.id == "timer")
        #expect(resolution.queued.map(\.id) == ["quickActions"])
    }

    @Test func onlyCommandCenterActivitiesLeaveTheNotchIdleButListed() {
        let resolution = resolve([
            makeActivity("cpu", priority: .ambient, placement: .commandCenter),
            makeActivity("volume", priority: ActivityPriority(rawValue: 14), placement: .commandCenter),
        ])

        #expect(resolution.primary == nil)
        #expect(resolution.queued.map(\.id) == ["volume", "cpu"])
        #expect(resolution.all.map(\.id) == ["volume", "cpu"])
    }

    @Test func incumbentRuleOnlyConsidersNotchActivities() {
        let resolution = resolve([
            makeActivity("shown", priority: .active),
            makeActivity("newer", priority: .active),
            makeActivity("listed", priority: .active, placement: .commandCenter),
        ], current: ActivityKey(source: .testA, id: "shown"))

        #expect(resolution.primary?.id == "shown")
    }

    @Test func movingAnActivityToTheCommandCenterReleasesTheNotch() {
        let resolution = resolve([
            makeActivity("music", priority: .passive),
            makeActivity("volume", priority: .timeSensitive, placement: .commandCenter),
        ], current: ActivityKey(source: .testA, id: "volume"))

        #expect(resolution.primary?.id == "music")
    }
}

@MainActor
final class DisplayRecordingProvider: ActivityProvider {
    let source: ActivitySource
    private(set) var publisher: ActivityPublisher?
    private(set) var displayedHistory: [Set<NotchActivity.ID>] = []
    private(set) var adjustments: [(action: String, value: Double)] = []
    var handlesScroll = false
    private(set) var scrolls: [Double] = []

    init(source: ActivitySource) {
        self.source = source
    }

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
    }

    func displayedActivitiesChanged(_ ids: Set<NotchActivity.ID>) {
        displayedHistory.append(ids)
    }

    func adjust(actionID: ActivityAction.ID, to value: Double, on activityID: NotchActivity.ID) {
        adjustments.append((actionID, value))
    }

    func handleNotchScroll(_ delta: Double) -> Bool {
        guard handlesScroll else { return false }
        scrolls.append(delta)
        return true
    }
}

@MainActor
struct EngineInputRoutingTests {
    let engine = ActivityEngine(schedulesExpiry: false)

    @Test func providersHearOnlyAboutTheirOwnDisplayedActivities() {
        let a = DisplayRecordingProvider(source: .testA)
        let b = DisplayRecordingProvider(source: .testB)
        engine.register(a)
        engine.register(b)

        engine.updateDisplayedActivities([ActivityKey(source: .testA, id: "cpu")])
        engine.updateDisplayedActivities([ActivityKey(source: .testA, id: "cpu"), ActivityKey(source: .testB, id: "timer")])
        engine.updateDisplayedActivities([])

        #expect(a.displayedHistory == [["cpu"], []])
        #expect(b.displayedHistory == [["timer"], []])
    }

    @Test func unchangedDisplayIsNotReported() {
        let a = DisplayRecordingProvider(source: .testA)
        engine.register(a)
        let keys: Set = [ActivityKey(source: .testA, id: "cpu")]

        engine.updateDisplayedActivities(keys)
        engine.updateDisplayedActivities(keys)

        #expect(a.displayedHistory == [["cpu"]])
    }

    @Test func aProviderRegisteredWhileItsActivityIsDisplayedIsTold() {
        engine.updateDisplayedActivities([ActivityKey(source: .testA, id: "cpu")])
        let a = DisplayRecordingProvider(source: .testA)

        engine.register(a)

        #expect(a.displayedHistory == [["cpu"]])
    }

    @Test func adjustmentsAreRoutedAndClamped() {
        let a = DisplayRecordingProvider(source: .testA)
        engine.register(a)

        engine.adjust(actionID: "setVolume", to: 1.7, on: ActivityKey(source: .testA, id: "volume"))
        engine.adjust(actionID: "setVolume", to: 0.3, on: ActivityKey(source: .testB, id: "volume"))

        #expect(a.adjustments.map(\.action) == ["setVolume"])
        #expect(a.adjustments.map(\.value) == [1])
    }

    @Test func scrollGoesToTheFirstProviderThatHandlesIt() {
        let a = DisplayRecordingProvider(source: .testA)
        let b = DisplayRecordingProvider(source: .testB)
        b.handlesScroll = true
        engine.register(a)
        engine.register(b)

        #expect(engine.routeNotchScroll(1.5))
        #expect(b.scrolls == [1.5])

        b.handlesScroll = false
        #expect(!engine.routeNotchScroll(1))
    }

    @Test func registeredSourcesKeepRegistrationOrder() {
        engine.register(DisplayRecordingProvider(source: .testB))
        engine.register(DisplayRecordingProvider(source: .testA))
        #expect(engine.registeredSources == [.testB, .testA])
        #expect(engine.isRegistered(.testA))

        engine.unregister(.testB)
        #expect(engine.registeredSources == [.testA])
    }
}
