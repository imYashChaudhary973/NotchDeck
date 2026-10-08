import Foundation
import Testing
@testable import NotchDeck

struct NotchDisplayTests {
    let timer = makeActivity("timer", priority: .active, kind: .timer)
    let cpu = makeActivity("cpu", priority: .ambient, placement: .commandCenter, kind: .system)
    let actions = makeActivity("actions", priority: .passive, placement: .commandCenter, kind: .quickActions)

    private var resolution: ActivityResolution {
        ActivityResolution(primary: timer, queued: [actions, cpu])
    }

    @Test func idleAndShelfDisplayNothing() {
        #expect(NotchDisplay.displayedKeys(state: .idle, resolution: resolution, selectedSection: .overview).isEmpty)
        #expect(NotchDisplay.displayedKeys(state: .shelf, resolution: resolution, selectedSection: .overview).isEmpty)
    }

    @Test func compactStatesDisplayOnlyThePrimary() {
        #expect(NotchDisplay.displayedKeys(state: .liveActivity, resolution: resolution, selectedSection: .overview) == [timer.key])
        #expect(NotchDisplay.displayedKeys(state: .peek, resolution: resolution, selectedSection: .overview) == [timer.key])
    }

    @Test func expandedDisplaysTheSelectedSection() {
        #expect(NotchDisplay.displayedKeys(state: .expanded, resolution: resolution, selectedSection: .overview)
            == [timer.key, actions.key, cpu.key])
        #expect(NotchDisplay.displayedKeys(state: .expanded, resolution: resolution, selectedSection: .kind(.system))
            == [cpu.key])
    }

    @Test func activitiesBehindMoreAreNotDisplayed() {
        let extra = (0..<6).map { makeActivity("m\($0)", priority: .ambient, placement: .commandCenter) }
        let crowded = ActivityResolution(primary: timer, queued: extra)

        let keys = NotchDisplay.displayedKeys(state: .expanded, resolution: crowded, selectedSection: .overview)

        #expect(keys.count == 1 + CommandCenterLayout.maxWidgetRows)
        #expect(!keys.contains(extra.last!.key))
    }

    @Test func scrollStepsFollowThePhysicalDirection() {
        // A mouse wheel notch is one step.
        #expect(NotchScroll.steps(deltaY: 1, isPrecise: false, isInverted: false) == 1)
        // Natural scrolling reports the fingers moving up as a negative delta.
        #expect(NotchScroll.steps(deltaY: -32, isPrecise: true, isInverted: true) == 2)
        #expect(NotchScroll.steps(deltaY: -16, isPrecise: true, isInverted: false) == -1)
    }
}
