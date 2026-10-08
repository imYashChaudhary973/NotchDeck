import Foundation

/// How long Keep Awake stays on.
enum KeepAwakeDuration: CaseIterable, Sendable {
    case thirtyMinutes
    case oneHour
    case twoHours
    case indefinite

    var seconds: TimeInterval? {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .indefinite: nil
        }
    }

    var title: String {
        switch self {
        case .thirtyMinutes: "30 Min"
        case .oneHour: "1 Hour"
        case .twoHours: "2 Hours"
        case .indefinite: "Indefinitely"
        }
    }

    var actionID: ActivityAction.ID {
        switch self {
        case .thirtyMinutes: "for30m"
        case .oneHour: "for1h"
        case .twoHours: "for2h"
        case .indefinite: "indefinitely"
        }
    }
}

/// Whether Keep Awake is on, and until when. Persisted so it survives a relaunch.
enum KeepAwakeSession: Codable, Equatable, Sendable {
    case off
    case until(Date)
    case indefinite

    init(duration: KeepAwakeDuration, now: Date) {
        self = duration.seconds.map { .until(now.addingTimeInterval($0)) } ?? .indefinite
    }

    func isActive(at now: Date) -> Bool {
        switch self {
        case .off: false
        case .until(let end): end > now
        case .indefinite: true
        }
    }

    /// The session as of `now`: a timed session that has ended is off.
    func normalized(at now: Date) -> KeepAwakeSession {
        isActive(at: now) ? self : .off
    }
}

/// Keeps the Mac awake with a supported IOKit power assertion, for a preset time or until turned off.
///
/// While on, it shows a subtle Live Activity (a cup beside the notch). While off, its switch is
/// only listed in the command center. The assertion is released when the session ends, when the
/// feature is turned off, and when NotchDeck quits; an active session is restored after relaunch.
@MainActor
final class KeepAwakeProvider: ActivityProvider {
    let source = ActivitySource(rawValue: "keepAwake")
    static let activityID = "keepAwake"
    static let persistenceKey = "keepAwake.session"

    enum ActionID {
        static let toggle = "toggle"
        static let turnOff = "turnOff"
    }

    private(set) var session: KeepAwakeSession = .off
    /// Called after the session changes (e.g. to refresh the Quick Actions tile).
    var onChange: (() -> Void)?

    private var publisher: ActivityPublisher?
    private var endTask: Task<Void, Never>?
    private let assertion: any PowerAssertionControlling
    private let defaults: UserDefaults
    private let now: () -> Date
    private let schedulesEnd: Bool

    init(
        assertion: any PowerAssertionControlling = IOKitPowerAssertion(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { .now },
        schedulesEnd: Bool = true
    ) {
        self.assertion = assertion
        self.defaults = defaults
        self.now = now
        self.schedulesEnd = schedulesEnd
    }

    var isActive: Bool { session.isActive(at: now()) }

    // MARK: ActivityProvider

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
        apply(Self.load(from: defaults).normalized(at: now()))
    }

    /// Releases the assertion but keeps the saved session, so it is restored on the next launch.
    func stop() {
        endTask?.cancel()
        endTask = nil
        assertion.release()
        publisher = nil
    }

    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
        switch actionID {
        case ActionID.toggle:
            toggle()
        case ActionID.turnOff:
            turnOff()
        default:
            if let duration = KeepAwakeDuration.allCases.first(where: { $0.actionID == actionID }) {
                turnOn(for: duration)
            }
        }
    }

    // MARK: Commands

    func turnOn(for duration: KeepAwakeDuration) {
        apply(KeepAwakeSession(duration: duration, now: now()))
    }

    func turnOff() {
        apply(.off)
    }

    /// Turns on until turned off, or turns off.
    func toggle() {
        isActive ? turnOff() : turnOn(for: .indefinite)
    }

    /// Ends a timed session that is due. Called by the scheduled wake-up, or directly in tests.
    func endIfDue() {
        let normalized = session.normalized(at: now())
        if normalized != session { apply(normalized) }
    }

    // MARK: State

    private func apply(_ newSession: KeepAwakeSession) {
        session = newSession
        save()

        endTask?.cancel()
        endTask = nil
        switch newSession {
        case .off:
            assertion.release()
        case .indefinite:
            assertion.acquire(reason: "NotchDeck Keep Awake", timeout: nil)
        case .until(let end):
            let remaining = end.timeIntervalSince(now())
            assertion.acquire(reason: "NotchDeck Keep Awake", timeout: remaining)
            if schedulesEnd {
                endTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(max(remaining, 0)), tolerance: .seconds(1), clock: .continuous)
                    guard !Task.isCancelled else { return }
                    self?.endIfDue()
                }
            }
        }
        publisher?.publish(Self.activity(for: newSession, now: now(), source: source))
        onChange?()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Self.persistenceKey)
        }
    }

    static func load(from defaults: UserDefaults) -> KeepAwakeSession {
        guard let data = defaults.data(forKey: persistenceKey),
              let session = try? JSONDecoder().decode(KeepAwakeSession.self, from: data) else {
            return .off
        }
        return session
    }

    // MARK: Activity

    static func activity(for session: KeepAwakeSession, now: Date, source: ActivitySource) -> NotchActivity {
        let isOn = session.isActive(at: now)
        let stateText: String = switch session.normalized(at: now) {
        case .off: "Off"
        case .indefinite: "Until turned off"
        case .until(let end): "Until \(end.formatted(date: .omitted, time: .shortened))"
        }
        return NotchActivity(
            id: activityID,
            source: source,
            kind: .system,
            priority: .ambient,
            // Off, it is only a switch in the command center; on, it earns a subtle Live Activity.
            placement: isOn ? .notch : .commandCenter,
            title: "Keep Awake",
            subtitle: isOn ? "Display won't sleep" : nil,
            presentation: ActivityPresentation(
                symbolName: "cup.and.saucer.fill",
                accent: isOn ? .yellow : .neutral,
                statusText: isOn ? stateText : nil,
                content: .toggle(ToggleContent(isOn: isOn, actionID: ActionID.toggle, stateText: stateText))
            ),
            actions: KeepAwakeDuration.allCases.map { ActivityAction(id: $0.actionID, title: $0.title) }
        )
    }
}
