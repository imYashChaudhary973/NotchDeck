import Foundation
import Testing
@testable import NotchDeck

struct CalendarRulesTests {
    let start = Date(timeIntervalSinceReferenceDate: 100_000)

    private func event(start: Date? = nil, duration: TimeInterval = 1800, isAllDay: Bool = false) -> CalendarEvent {
        let start = start ?? self.start
        return CalendarEvent(id: "e", title: "Design Review", start: start, end: start.addingTimeInterval(duration), isAllDay: isAllDay)
    }

    private func priority(at offset: TimeInterval, rules: CalendarRules = .standard, event: CalendarEvent? = nil) -> ActivityPriority? {
        let event = event ?? self.event()
        return rules.rule(for: event, at: event.start.addingTimeInterval(offset))?.priority
    }

    @Test func defaultRulesFollowThePlan() {
        #expect(priority(at: -16 * 60) == nil)
        #expect(priority(at: -15 * 60) == .active)
        #expect(priority(at: -6 * 60) == .active)
        #expect(priority(at: -5 * 60) == .timeSensitive)
        #expect(priority(at: -61) == .timeSensitive)
        #expect(priority(at: -60) == .attentionRequired)
        #expect(priority(at: 0) == .attentionRequired)
        #expect(priority(at: 4 * 60) == .attentionRequired)
        // After the grace period the meeting leaves the notch.
        #expect(priority(at: 5 * 60) == nil)
    }

    @Test func gracePeriodEndsWithAShortMeeting() {
        let short = event(duration: 120)
        #expect(priority(at: 119, event: short) == .attentionRequired)
        #expect(priority(at: 120, event: short) == nil)
        #expect(CalendarRules.standard.notchEnd(for: short) == short.end)
    }

    @Test func allDayEventsNeverTakeTheNotch() {
        let allDay = event(duration: 86_400, isAllDay: true)
        #expect(priority(at: -60, event: allDay) == nil)
        #expect(priority(at: 0, event: allDay) == nil)
        #expect(CalendarRules.standard.boundaries(for: allDay).isEmpty)
    }

    @Test func notchLeadTimeIsConfigurable() {
        let early = CalendarRules(notchLeadTime: 30 * 60)
        #expect(early.notchLeadTime == 30 * 60)
        #expect(priority(at: -29 * 60, rules: early) == .active)
        #expect(priority(at: -4 * 60, rules: early) == .timeSensitive)

        // With a 5-minute lead, the meeting arrives already Time Sensitive.
        let late = CalendarRules(notchLeadTime: 5 * 60)
        #expect(late.rules.map(\.priority) == [.timeSensitive, .attentionRequired])
        #expect(priority(at: -6 * 60, rules: late) == nil)
        #expect(priority(at: -5 * 60, rules: late) == .timeSensitive)
        #expect(priority(at: -30, rules: late) == .attentionRequired)
    }

    @Test func customRulesAreSortedByLeadTime() {
        let rules = CalendarRules(rules: [
            MeetingRule(name: "Now", leadTime: 0, priority: .critical),
            MeetingRule(name: "Hour", leadTime: 3600, priority: .passive),
        ], startingGracePeriod: 0)
        #expect(rules.rules.map(\.name) == ["Hour", "Now"])
        #expect(priority(at: -1800, rules: rules) == .passive)
        #expect(priority(at: -1, rules: rules) == .passive)
        #expect(priority(at: 0, rules: rules) == nil) // grace 0: gone at the start
    }

    @Test func boundariesCoverEveryRuleChange() {
        let boundaries = CalendarRules.standard.boundaries(for: event())
        #expect(Set(boundaries) == [
            start.addingTimeInterval(-15 * 60),
            start.addingTimeInterval(-5 * 60),
            start.addingTimeInterval(-60),
            start,
            start.addingTimeInterval(5 * 60),
        ])
    }

    @Test func countdownTextsRoundUpToTheMinute() {
        #expect(MeetingCountdown.compactText(start: start, at: start.addingTimeInterval(-12 * 60)) == "12m")
        #expect(MeetingCountdown.compactText(start: start, at: start.addingTimeInterval(-(11 * 60 + 1))) == "12m")
        #expect(MeetingCountdown.compactText(start: start, at: start.addingTimeInterval(-1)) == "1m")
        #expect(MeetingCountdown.compactText(start: start, at: start) == "Now")
        #expect(MeetingCountdown.statusText(start: start, at: start.addingTimeInterval(-180)) == "In 3 min")
        #expect(MeetingCountdown.statusText(start: start, at: start.addingTimeInterval(30)) == "Starting now")
    }

    @Test func countdownChangesOncePerMinute() {
        #expect(MeetingCountdown.nextChange(start: start, after: start.addingTimeInterval(-12 * 60)) == start.addingTimeInterval(-11 * 60))
        #expect(MeetingCountdown.nextChange(start: start, after: start.addingTimeInterval(-30)) == start)
        #expect(MeetingCountdown.nextChange(start: start, after: start) == nil)
    }

    @Test func calendarColorsMapToTheNearestAccent() {
        #expect(ActivityAccent.nearest(hue: 0.0, saturation: 0.8, brightness: 0.9) == .red)
        #expect(ActivityAccent.nearest(hue: 0.08, saturation: 0.8, brightness: 0.9) == .orange)
        #expect(ActivityAccent.nearest(hue: 0.33, saturation: 0.8, brightness: 0.9) == .green)
        #expect(ActivityAccent.nearest(hue: 0.6, saturation: 0.8, brightness: 0.9) == .blue)
        #expect(ActivityAccent.nearest(hue: 0.78, saturation: 0.8, brightness: 0.9) == .purple)
        #expect(ActivityAccent.nearest(hue: 0.9, saturation: 0.8, brightness: 0.9) == .pink)
        #expect(ActivityAccent.nearest(hue: 0.6, saturation: 0.05, brightness: 0.9) == .neutral)
    }
}

struct MeetingLinkDetectorTests {
    private func detect(url: String? = nil, location: String? = nil, notes: String? = nil) -> String? {
        MeetingLinkDetector.meetingURL(url: url.flatMap(URL.init(string:)), location: location, notes: notes)?.absoluteString
    }

    @Test func findsKnownMeetingServices() {
        #expect(detect(url: "https://acme.zoom.us/j/123456789?pwd=abc") == "https://acme.zoom.us/j/123456789?pwd=abc")
        #expect(detect(location: "https://meet.google.com/abc-defg-hij") == "https://meet.google.com/abc-defg-hij")
        #expect(detect(notes: "Join Microsoft Teams Meeting <https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0?context=y>")
            == "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0?context=y")
        #expect(detect(notes: "Webex: https://acme.webex.com/acme/j.php?MTID=m1") == "https://acme.webex.com/acme/j.php?MTID=m1")
        #expect(detect(notes: "FaceTime https://facetime.apple.com/join#v=1&p=abc") != nil)
    }

    @Test func prefersTheEventURLThenLocationThenNotes() {
        #expect(detect(
            url: "https://zoom.us/j/1",
            location: "https://meet.google.com/aaa-bbbb-ccc",
            notes: "https://teams.microsoft.com/l/meetup-join/x"
        ) == "https://zoom.us/j/1")
        #expect(detect(
            url: "https://docs.example.com/agenda",
            location: "Room 4",
            notes: "Agenda https://docs.example.com/a then join https://meet.google.com/aaa-bbbb-ccc"
        ) == "https://meet.google.com/aaa-bbbb-ccc")
    }

    @Test func ignoresUnrelatedLinks() {
        #expect(detect(url: "https://docs.example.com/agenda") == nil)
        #expect(detect(notes: "See https://example.com/zoom.us/j/1 for details") == nil)
        #expect(detect(notes: "Zoom marketing: https://zoom.us/pricing") == nil)
        #expect(detect(location: "Conference Room B, 2nd floor") == nil)
        #expect(detect() == nil)
    }

    @Test func aLocationThatIsOnlyAWebLinkIsUsed() {
        #expect(detect(location: " https://video.example.com/room/42 ") == "https://video.example.com/room/42")
        #expect(detect(location: "Room 4 (backup: https://video.example.com/room/42)") == nil)
    }

    @Test func onlyWebLinksAreAccepted() {
        #expect(detect(url: "file:///Applications/zoom.us.app") == nil)
        #expect(detect(url: "javascript:alert(1)") == nil)
        #expect(!MeetingLinkDetector.isMeetingLink(URL(string: "ftp://zoom.us/j/1")!))
        #expect(!MeetingLinkDetector.isMeetingLink(URL(string: "https://notzoom.us/j/1")!))
    }
}
