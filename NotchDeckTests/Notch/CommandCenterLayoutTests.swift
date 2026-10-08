import Foundation
import Testing
@testable import NotchDeck

struct CommandCenterLayoutTests {
    private func activity(_ id: String, kind: ActivityKind, priority: ActivityPriority = .passive) -> NotchActivity {
        NotchActivity(id: id, source: .testA, kind: kind, priority: priority, title: id,
                      presentation: ActivityPresentation(symbolName: "circle"))
    }

    private func resolution(_ activities: [NotchActivity]) -> ActivityResolution {
        var store = ActivityStore()
        activities.forEach { store.upsert($0) }
        return ActivityResolver().resolve(store.all, current: nil, now: .now)
    }

    @Test func emptyResolutionHasOnlyOverviewAndNoTabs() {
        let layout = CommandCenterLayout.make(resolution: .empty, selected: .overview)
        #expect(layout.sections == [.overview])
        #expect(!layout.showsTabs)
        #expect(layout.featured == nil)
        #expect(layout.widgets.isEmpty)
    }

    @Test func sectionsFollowKindOrderNotPublishOrder() {
        let layout = CommandCenterLayout.make(
            resolution: resolution([activity("cpu", kind: .system), activity("song", kind: .music), activity("call", kind: .meeting)]),
            selected: .overview
        )
        #expect(layout.sections == [.overview, .kind(.music), .kind(.meeting), .kind(.system)])
        #expect(layout.showsTabs)
    }

    @Test func overviewFeaturesThePrimaryActivity() {
        let layout = CommandCenterLayout.make(
            resolution: resolution([activity("song", kind: .music), activity("agent", kind: .agent, priority: .attentionRequired)]),
            selected: .overview
        )
        #expect(layout.featured?.id == "agent")
        #expect(layout.widgets.map(\.id) == ["song"])
    }

    @Test func kindSectionShowsOnlyThatKind() {
        let layout = CommandCenterLayout.make(
            resolution: resolution([activity("song", kind: .music), activity("cpu", kind: .system), activity("mem", kind: .system)]),
            selected: .kind(.system)
        )
        #expect(layout.selectedSection == .kind(.system))
        #expect(Set([layout.featured?.id] + layout.widgets.map(\.id)) == ["cpu", "mem"])
    }

    @Test func missingSelectionFallsBackToOverview() {
        let layout = CommandCenterLayout.make(resolution: resolution([activity("song", kind: .music)]), selected: .kind(.agent))
        #expect(layout.selectedSection == .overview)
        #expect(layout.featured?.id == "song")
    }

    @Test func widgetColumnIsCappedWithHiddenCount() {
        let many = (0..<8).map { activity("a\($0)", kind: .generic) }
        let layout = CommandCenterLayout.make(resolution: resolution(many), selected: .overview)
        #expect(layout.widgets.count == CommandCenterLayout.maxWidgetRows)
        #expect(layout.hiddenWidgetCount == 8 - 1 - CommandCenterLayout.maxWidgetRows)
    }

    @Test func attentionMarksTheActivitysSection() {
        let layout = CommandCenterLayout.make(
            resolution: resolution([activity("song", kind: .music), activity("agent", kind: .agent, priority: .attentionRequired)]),
            selected: .overview
        )
        #expect(layout.attentionSections == [.kind(.agent)])
    }
}

@MainActor
struct NotchRevealTests {
    private func resolution(primary: NotchActivity?) -> ActivityResolution {
        ActivityResolution(primary: primary, queued: [])
    }

    private func activity(_ id: String, priority: ActivityPriority, revealsOnUpdate: Bool = false, title: String = "t") -> NotchActivity {
        NotchActivity(id: id, source: .testA, kind: .generic, priority: priority, title: title,
                      presentation: ActivityPresentation(symbolName: "circle", revealsOnUpdate: revealsOnUpdate))
    }

    @Test func attentionPriorityRevealsOnAppearanceOnly() {
        let agent = activity("agent", priority: .attentionRequired)
        #expect(NotchController.shouldReveal(from: .empty, to: resolution(primary: agent)))
        #expect(!NotchController.shouldReveal(from: resolution(primary: agent), to: resolution(primary: agent)))
    }

    @Test func escalationToAttentionReveals() {
        let timer = activity("timer", priority: .active)
        let finished = activity("timer", priority: .attentionRequired)
        #expect(NotchController.shouldReveal(from: resolution(primary: timer), to: resolution(primary: finished)))
    }

    @Test func ordinaryPriorityDoesNotReveal() {
        #expect(!NotchController.shouldReveal(from: .empty, to: resolution(primary: activity("song", priority: .passive))))
    }

    @Test func hudActivityRevealsOnEveryChange() {
        let v1 = activity("volume", priority: .active, revealsOnUpdate: true, title: "50%")
        let v2 = activity("volume", priority: .active, revealsOnUpdate: true, title: "56%")
        #expect(NotchController.shouldReveal(from: .empty, to: resolution(primary: v1)))
        #expect(NotchController.shouldReveal(from: resolution(primary: v1), to: resolution(primary: v2)))
        #expect(!NotchController.shouldReveal(from: resolution(primary: v2), to: resolution(primary: v2)))
    }
}

struct ActivityContentTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func playingMediaAdvancesAndClampsToDuration() {
        let media = MediaContent(isPlaying: true, position: 60, positionDate: start, duration: 100)
        #expect(media.position(at: start.addingTimeInterval(10)) == 70)
        #expect(media.position(at: start.addingTimeInterval(500)) == 100)
    }

    @Test func pausedMediaStaysPut() {
        let media = MediaContent(isPlaying: false, position: 60, positionDate: start, duration: 100)
        #expect(media.position(at: start.addingTimeInterval(30)) == 60)
    }

    @Test func mediaPositionNeverGoesBackwardsBeforePositionDate() {
        let media = MediaContent(isPlaying: true, position: 60, positionDate: start, duration: nil)
        #expect(media.position(at: start.addingTimeInterval(-5)) == 60)
    }

    @Test func levelAndMetricValuesAreClamped() {
        #expect(LevelContent(value: 1.4).value == 1)
        #expect(LevelContent(value: -1).value == 0)
        #expect(MetricContent(value: 2, valueText: "200%").value == 1)
    }
}
