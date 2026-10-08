import Foundation
import Testing
@testable import NotchDeck

struct TimerCollectionTests {
    let start = Date(timeIntervalSinceReferenceDate: 10_000)

    @Test func startCreatesARunningTimerWithADefaultLabel() {
        var timers = TimerCollection()
        let id = timers.start(duration: 25 * 60, now: start)

        let timer = timers.timer(id)
        #expect(timer?.label == "25 min timer")
        #expect(timer?.state == .running(endsAt: start.addingTimeInterval(1500)))
        #expect(timer?.remaining(at: start.addingTimeInterval(100)) == 1400)
    }

    @Test func customLabelIsTrimmedAndBlankFallsBack() {
        var timers = TimerCollection()
        let named = timers.start(duration: 90, label: "  Tea ", now: start)
        let blank = timers.start(duration: 90, label: "   ", now: start)

        #expect(timers.timer(named)?.label == "Tea")
        #expect(timers.timer(blank)?.label == "1 min 30 sec timer")
    }

    @Test func durationIsClamped() {
        var timers = TimerCollection()
        let tooShort = timers.start(duration: 0, now: start)
        let tooLong = timers.start(duration: 100 * 3600, now: start)

        #expect(timers.timer(tooShort)?.duration == 1)
        #expect(timers.timer(tooLong)?.duration == TimerRules.durationRange.upperBound)
    }

    @Test func pauseAndResumeKeepTheRemainingTime() {
        var timers = TimerCollection()
        let id = timers.start(duration: 600, now: start)

        timers.pause(id, now: start.addingTimeInterval(100))
        #expect(timers.timer(id)?.state == .paused(remaining: 500))
        // Time passing while paused changes nothing.
        #expect(timers.timer(id)?.remaining(at: start.addingTimeInterval(10_000)) == 500)

        timers.resume(id, now: start.addingTimeInterval(1_000))
        #expect(timers.timer(id)?.state == .running(endsAt: start.addingTimeInterval(1_500)))
    }

    @Test func pausingAPausedTimerOrResumingARunningOneDoesNothing() {
        var timers = TimerCollection()
        let id = timers.start(duration: 600, now: start)
        timers.resume(id, now: start.addingTimeInterval(50))
        #expect(timers.timer(id)?.state == .running(endsAt: start.addingTimeInterval(600)))

        timers.pause(id, now: start.addingTimeInterval(100))
        timers.pause(id, now: start.addingTimeInterval(200))
        #expect(timers.timer(id)?.state == .paused(remaining: 500))
    }

    @Test func addTimeExtendsRunningAndPausedTimers() {
        var timers = TimerCollection()
        let running = timers.start(duration: 600, now: start)
        let paused = timers.start(duration: 600, now: start)
        timers.pause(paused, now: start)

        timers.addTime(60, to: running, now: start)
        timers.addTime(60, to: paused, now: start)

        #expect(timers.timer(running)?.state == .running(endsAt: start.addingTimeInterval(660)))
        #expect(timers.timer(paused)?.state == .paused(remaining: 660))
    }

    @Test func phasesEscalateNearZero() {
        var timers = TimerCollection()
        let id = timers.start(duration: 300, now: start)
        let timer = timers.timer(id)!

        #expect(timer.phase(at: start) == .running)
        #expect(timer.phase(at: start.addingTimeInterval(239)) == .running)
        #expect(timer.phase(at: start.addingTimeInterval(240)) == .finalMinute)
        #expect(timer.phase(at: start.addingTimeInterval(290)) == .finalSeconds)

        #expect(TimerPhase.running.priority == .active)
        #expect(TimerPhase.finalMinute.priority.rawValue == 35)
        #expect(TimerPhase.finalSeconds.priority == .timeSensitive)
        #expect(TimerPhase.finished.priority == .attentionRequired)
        #expect(TimerPhase.paused.priority < TimerPhase.running.priority)
    }

    @Test func advanceFinishesTimersAndRemovesThemAfterTheAlert() {
        var timers = TimerCollection()
        let id = timers.start(duration: 60, now: start)

        #expect(timers.advance(to: start.addingTimeInterval(59)).isEmpty)

        let finished = timers.advance(to: start.addingTimeInterval(60))
        #expect(finished.map(\.id) == [id])
        #expect(timers.timer(id)?.state == .finished(at: start.addingTimeInterval(60)))
        #expect(timers.timer(id)?.phase(at: start.addingTimeInterval(61)) == .finished)

        // Not announced twice.
        #expect(timers.advance(to: start.addingTimeInterval(65)).isEmpty)

        timers.advance(to: start.addingTimeInterval(60 + TimerRules.finishedAlertDuration))
        #expect(timers.isEmpty)
    }

    @Test func timersThatEndedLongAgoAreDroppedWithoutAnnouncement() {
        var timers = TimerCollection()
        timers.start(duration: 60, now: start)

        let finished = timers.advance(to: start.addingTimeInterval(3_600))

        #expect(finished.isEmpty)
        #expect(timers.isEmpty)
    }

    @Test func mostRelevantPrefersFinishedThenSoonestRunningThenPaused() {
        var timers = TimerCollection()
        let paused = timers.start(duration: 30, now: start)
        timers.pause(paused, now: start)
        #expect(timers.mostRelevant(at: start) == paused)

        let long = timers.start(duration: 3_600, now: start)
        let short = timers.start(duration: 600, now: start)
        #expect(timers.mostRelevant(at: start) == short)

        timers.remove(short)
        #expect(timers.mostRelevant(at: start) == long)

        let quick = timers.start(duration: 5, now: start)
        timers.advance(to: start.addingTimeInterval(5))
        #expect(timers.mostRelevant(at: start.addingTimeInterval(5)) == quick)
    }

    @Test func nextTransitionIsTheEarliestPhaseChange() {
        var timers = TimerCollection()
        let id = timers.start(duration: 300, now: start)

        #expect(timers.nextTransition(after: start) == start.addingTimeInterval(240))
        #expect(timers.nextTransition(after: start.addingTimeInterval(240)) == start.addingTimeInterval(290))
        #expect(timers.nextTransition(after: start.addingTimeInterval(290)) == start.addingTimeInterval(300))

        timers.advance(to: start.addingTimeInterval(300))
        #expect(timers.nextTransition(after: start.addingTimeInterval(300))
            == start.addingTimeInterval(300 + TimerRules.finishedAlertDuration))

        timers.restart(id, now: start.addingTimeInterval(300))
        timers.pause(id, now: start.addingTimeInterval(300))
        #expect(timers.nextTransition(after: start.addingTimeInterval(300)) == nil)
    }

    @Test func restartRunsTheOriginalDurationAgain() {
        var timers = TimerCollection()
        let id = timers.start(duration: 60, now: start)
        timers.advance(to: start.addingTimeInterval(60))

        timers.restart(id, now: start.addingTimeInterval(62))

        #expect(timers.timer(id)?.state == .running(endsAt: start.addingTimeInterval(122)))
    }

    @Test func theNumberOfTimersIsLimitedDroppingIdleOnesFirst() {
        var timers = TimerCollection()
        let paused = timers.start(duration: 60, now: start)
        timers.pause(paused, now: start)
        for _ in 0..<TimerRules.maximumTimers {
            timers.start(duration: 60, now: start)
        }

        #expect(timers.timers.count == TimerRules.maximumTimers)
        #expect(timers.timer(paused) == nil)
    }

    @Test func collectionSurvivesEncoding() throws {
        var timers = TimerCollection()
        timers.start(duration: 60, label: "Tea", now: start)
        let paused = timers.start(duration: 120, now: start)
        timers.pause(paused, now: start.addingTimeInterval(20))

        let decoded = try JSONDecoder().decode(TimerCollection.self, from: JSONEncoder().encode(timers))

        #expect(decoded == timers)
    }

    @Test func formatting() {
        #expect(TimerRules.durationLabel(5 * 60) == "5 min")
        #expect(TimerRules.durationLabel(3600) == "1 hr")
        #expect(TimerRules.durationLabel(5400) == "1 hr 30 min")
        #expect(TimerRules.durationLabel(45) == "45 sec")
        #expect(TimerRules.shortDurationLabel(25 * 60) == "25m")
        #expect(TimerRules.shortDurationLabel(3600) == "1h")
        #expect(TimerRules.clockText(245) == "4:05")
        #expect(TimerRules.clockText(3723) == "1:02:03")
        #expect(TimerRules.clockText(0.2) == "0:01")
    }
}
