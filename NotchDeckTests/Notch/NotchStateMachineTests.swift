import Testing
@testable import NotchDeck

struct NotchStateMachineTests {
    private func machine(
        hasActivity: Bool = false,
        peeksOnHover: Bool = true,
        collapsesWhenPointerExits: Bool = true,
        peeksForAttention: Bool = true
    ) -> NotchStateMachine {
        var machine = NotchStateMachine(configuration: .init(
            peeksOnHover: peeksOnHover,
            collapsesWhenPointerExits: collapsesWhenPointerExits,
            peeksForAttention: peeksForAttention
        ))
        if hasActivity {
            machine.handle(.activityAvailabilityChanged(hasActivity: true))
        }
        return machine
    }

    // MARK: Definition of Done path

    @Test func fullLifecycleIdleToLiveToPeekToExpandedToCollapse() {
        var sm = machine()
        #expect(sm.state == .idle)

        sm.handle(.activityAvailabilityChanged(hasActivity: true))
        #expect(sm.state == .liveActivity)

        sm.handle(.pointerEntered)
        #expect(sm.state == .peek)

        sm.handle(.clicked)
        #expect(sm.state == .expanded)

        sm.handle(.clickedOutside)
        #expect(sm.state == .liveActivity)
    }

    // MARK: Activity availability

    @Test func activityAvailabilityMovesBetweenIdleAndLive() {
        var sm = machine()
        let appeared = sm.handle(.activityAvailabilityChanged(hasActivity: true))
        #expect(appeared)
        #expect(sm.state == .liveActivity)
        let disappeared = sm.handle(.activityAvailabilityChanged(hasActivity: false))
        #expect(disappeared)
        #expect(sm.state == .idle)
    }

    @Test func activityChangesDoNotCloseExpanded() {
        var sm = machine(hasActivity: true)
        sm.handle(.clicked)

        sm.handle(.activityAvailabilityChanged(hasActivity: false))
        #expect(sm.state == .expanded)

        sm.handle(.clickedOutside)
        #expect(sm.state == .idle)
    }

    @Test func hoverPeekSurvivesActivityDisappearing() {
        var sm = machine(hasActivity: true)
        sm.handle(.pointerEntered)

        sm.handle(.activityAvailabilityChanged(hasActivity: false))

        #expect(sm.state == .peek)
    }

    // MARK: Hover

    @Test func hoverPeeksAndExitRestores() {
        var sm = machine()
        sm.handle(.pointerEntered)
        #expect(sm.state == .peek)
        #expect(sm.isPointerInside)

        sm.handle(.pointerExited)
        #expect(sm.state == .idle)
        #expect(!sm.isPointerInside)
    }

    @Test func hoverDoesNothingWhenDisabled() {
        var sm = machine(hasActivity: true, peeksOnHover: false)
        let changed = sm.handle(.pointerEntered)
        #expect(!changed)
        #expect(sm.state == .liveActivity)
        #expect(sm.isPointerInside)
    }

    @Test func pointerExitCollapsesExpandedWhenConfigured() {
        var sm = machine(hasActivity: true)
        sm.handle(.pointerEntered)
        sm.handle(.clicked)

        sm.handle(.pointerExited)

        #expect(sm.state == .liveActivity)
    }

    @Test func pointerExitKeepsExpandedWhenNotConfigured() {
        var sm = machine(hasActivity: true, collapsesWhenPointerExits: false)
        sm.handle(.pointerEntered)
        sm.handle(.clicked)

        sm.handle(.pointerExited)

        #expect(sm.state == .expanded)
    }

    // MARK: Clicks

    @Test func clickExpandsFromEveryRestingOrPeekState() {
        let setups: [[NotchEvent]] = [[], [.activityAvailabilityChanged(hasActivity: true)], [.pointerEntered]]
        for setup in setups {
            var sm = machine()
            setup.forEach { sm.handle($0) }
            sm.handle(.clicked)
            #expect(sm.state == .expanded)
        }
    }

    @Test func clickInsideExpandedIsIgnored() {
        var sm = machine()
        sm.handle(.clicked)
        let changed = sm.handle(.clicked)
        #expect(!changed)
        #expect(sm.state == .expanded)
    }

    @Test func outsideClickAndDismissCollapseTransientStates() {
        for event in [NotchEvent.clickedOutside, .dismiss] {
            var sm = machine(hasActivity: true)
            sm.handle(.clicked)
            sm.handle(event)
            #expect(sm.state == .liveActivity)
        }
    }

    @Test func outsideClickIsIgnoredWhenResting() {
        var sm = machine(hasActivity: true)
        let changed = sm.handle(.clickedOutside)
        #expect(!changed)
        #expect(sm.state == .liveActivity)
    }

    // MARK: Attention

    @Test func attentionPeeksAndTimesOut() {
        var sm = machine(hasActivity: true)
        sm.handle(.attentionRequested)
        #expect(sm.state == .peek)
        #expect(sm.isAttentionPeek)

        sm.handle(.peekTimedOut)
        #expect(sm.state == .liveActivity)
        #expect(!sm.isAttentionPeek)
    }

    @Test func attentionPeekStaysWhileHoveredThenClosesOnExit() {
        var sm = machine(hasActivity: true)
        sm.handle(.attentionRequested)
        sm.handle(.pointerEntered)
        #expect(!sm.isAttentionPeek)

        sm.handle(.peekTimedOut)
        #expect(sm.state == .peek)

        sm.handle(.pointerExited)
        #expect(sm.state == .liveActivity)
    }

    @Test func attentionPeekIgnoresPointerExitBeforeEngagement() {
        var sm = machine(hasActivity: true)
        sm.handle(.attentionRequested)
        let changed = sm.handle(.pointerExited)
        #expect(!changed)
        #expect(sm.state == .peek)
    }

    @Test func attentionPeekClosesWhenItsActivityDisappears() {
        var sm = machine(hasActivity: true)
        sm.handle(.attentionRequested)
        sm.handle(.activityAvailabilityChanged(hasActivity: false))
        #expect(sm.state == .idle)
    }

    @Test func attentionDoesNotInterruptExpandedOrShelf() {
        for open in [NotchEvent.clicked, .dragEntered] {
            var sm = machine(hasActivity: true)
            sm.handle(open)
            let state = sm.state
            let changed = sm.handle(.attentionRequested)
            #expect(!changed)
            #expect(sm.state == state)
        }
    }

    @Test func attentionPeekCanBeDisabled() {
        var sm = machine(hasActivity: true, peeksForAttention: false)
        let changed = sm.handle(.attentionRequested)
        #expect(!changed)
        #expect(sm.state == .liveActivity)
    }

    @Test func staleTimeoutDoesNotCloseHoverPeek() {
        var sm = machine()
        sm.handle(.pointerEntered)
        let changed = sm.handle(.peekTimedOut)
        #expect(!changed)
        #expect(sm.state == .peek)
    }

    // MARK: Drag

    @Test func dragOpensShelfFromAnyStateAndReturnsToRest() {
        for setup in [[], [NotchEvent.pointerEntered], [.clicked]] {
            var sm = machine(hasActivity: true)
            setup.forEach { sm.handle($0) }

            sm.handle(.dragEntered)
            #expect(sm.state == .shelf)

            sm.handle(.dragExited)
            #expect(sm.state == .liveActivity)
        }
    }

    @Test func dropReturnsShelfToRest() {
        var sm = machine()
        sm.handle(.dragEntered)
        sm.handle(.dropCompleted)
        #expect(sm.state == .idle)
    }

    @Test func clickDoesNotLeaveShelf() {
        var sm = machine()
        sm.handle(.dragEntered)
        let changed = sm.handle(.clicked)
        #expect(!changed)
        #expect(sm.state == .shelf)
    }

    @Test func dragExitOutsideShelfIsIgnored() {
        var sm = machine()
        sm.handle(.clicked)
        let changed = sm.handle(.dragExited)
        #expect(!changed)
        #expect(sm.state == .expanded)
    }

    // MARK: Robustness

    @Test func rapidEventSequenceNeverProducesInvalidState() {
        var sm = machine()
        let events: [NotchEvent] = [
            .activityAvailabilityChanged(hasActivity: true), .pointerEntered, .attentionRequested, .clicked,
            .dragEntered, .pointerExited, .dragExited, .activityAvailabilityChanged(hasActivity: false),
            .attentionRequested, .peekTimedOut, .clicked, .clicked, .clickedOutside, .dismiss, .dropCompleted,
        ]
        for _ in 0..<50 {
            for event in events.shuffled() {
                sm.handle(event)
                if !sm.state.isTransient {
                    #expect(sm.state == sm.restingState)
                }
                if sm.isAttentionPeek {
                    #expect(sm.state == .peek)
                }
            }
        }
    }
}
