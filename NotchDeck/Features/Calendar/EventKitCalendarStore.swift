import AppKit
import EventKit

/// `CalendarStore` backed by EventKit. Read-only: NotchDeck never creates or changes events.
@MainActor
final class EventKitCalendarStore: CalendarStore {
    private let store = EKEventStore()
    private var observers: [NSObjectProtocol] = []

    var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        @unknown default: .denied
        }
    }

    func requestAccess() async -> CalendarAuthorization {
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        return authorization
    }

    func calendars() -> [CalendarInfo] {
        guard authorization.canReadEvents else { return [] }
        return store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source?.title ?? "",
                    accent: Self.accent(for: calendar)
                )
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    func events(from start: Date, to end: Date, excludingCalendars excluded: Set<String>) -> [CalendarEvent] {
        guard authorization.canReadEvents, start < end else { return [] }
        let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { event in
                event.status != .canceled
                    && event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined
            }
            .map(Self.makeEvent)
            .sorted { $0.start < $1.start }
    }

    func startObserving(onChange: @escaping @MainActor () -> Void) {
        stopObserving()
        let handler: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { onChange() }
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main, using: handler),
            center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: handler),
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: handler),
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: handler
            ),
        ]
    }

    func stopObserving() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: Conversion

    private static func makeEvent(_ event: EKEvent) -> CalendarEvent {
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let start = event.startDate ?? .distantPast
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CalendarEvent(
            // Recurring events share an identifier; the start date tells occurrences apart.
            id: "\(identifier)@\(Int(start.timeIntervalSinceReferenceDate))",
            title: title.isEmpty ? "Untitled Event" : title,
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            accent: event.calendar.map(accent(for:)) ?? .blue,
            meetingURL: MeetingLinkDetector.meetingURL(url: event.url, location: event.location, notes: event.notes)
        )
    }

    private static func accent(for calendar: EKCalendar) -> ActivityAccent {
        guard let color = calendar.cgColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB) else { return .blue }
        return .nearest(
            hue: Double(color.hueComponent),
            saturation: Double(color.saturationComponent),
            brightness: Double(color.brightnessComponent)
        )
    }
}
