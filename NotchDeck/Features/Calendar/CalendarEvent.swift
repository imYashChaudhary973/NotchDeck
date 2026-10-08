import Foundation

/// Calendar permission, as NotchDeck sees it.
enum CalendarAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    /// Blocked by a profile or parental controls; the user can't change it.
    case restricted
    /// Add-only access: NotchDeck can't read events.
    case writeOnly
    case fullAccess

    var canReadEvents: Bool { self == .fullAccess }
}

/// A calendar the user can include or exclude.
struct CalendarInfo: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    /// The account it belongs to, e.g. "iCloud".
    var sourceTitle: String
    var accent: ActivityAccent
}

/// One occurrence of a calendar event, reduced to what the notch needs.
struct CalendarEvent: Identifiable, Equatable, Sendable {
    /// Unique per occurrence (recurring events share an event identifier).
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String
    var accent: ActivityAccent
    /// A video-call link found in the event, if any.
    var meetingURL: URL?

    init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarID: String = "",
        accent: ActivityAccent = .blue,
        meetingURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = max(end, start)
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.accent = accent
        self.meetingURL = meetingURL
    }

    func isInProgress(at date: Date) -> Bool {
        start <= date && date < end
    }
}

/// Reads calendars and events. Abstracted so the calendar feature can be tested without EventKit.
@MainActor
protocol CalendarStore: AnyObject {
    var authorization: CalendarAuthorization { get }
    /// Asks the user for full calendar access (shows the system prompt once).
    func requestAccess() async -> CalendarAuthorization
    func calendars() -> [CalendarInfo]
    /// Events overlapping `start..<end` in the given calendars, sorted by start. Cancelled and
    /// declined events are left out.
    func events(from start: Date, to end: Date, excludingCalendars excluded: Set<String>) -> [CalendarEvent]
    /// Calls back (on the main actor) when events or calendars change, the clock changes, the day
    /// changes or the Mac wakes.
    func startObserving(onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

extension ActivityAccent {
    /// The accent closest to a calendar's color, from its HSB components (each 0…1).
    static func nearest(hue: Double, saturation: Double, brightness: Double) -> ActivityAccent {
        guard saturation >= 0.2, brightness >= 0.2 else { return .neutral }
        return switch hue {
        case ..<0.04: .red
        case ..<0.11: .orange
        case ..<0.19: .yellow
        case ..<0.45: .green
        case ..<0.72: .blue
        case ..<0.84: .purple
        case ..<0.95: .pink
        default: .red
        }
    }
}
