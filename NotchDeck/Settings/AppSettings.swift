import Foundation
import Observation

/// A feature that can be turned off in Settings.
enum Feature: CaseIterable, Sendable {
    case timers
    case keepAwake
    case systemMetrics
    case audio
    case quickActions
    case music
    case calendar

    var title: String {
        switch self {
        case .timers: "Timers"
        case .keepAwake: "Keep Awake"
        case .systemMetrics: "System metrics"
        case .audio: "Audio controls"
        case .quickActions: "Quick actions"
        case .music: "Now Playing"
        case .calendar: "Calendar"
        }
    }
}

/// User preferences, persisted in `UserDefaults`.
///
/// Add new settings as stored properties that write through in `didSet`, with a key in `Key`
/// and a default in `init`. Views and controllers observe this object via Observation.
@MainActor
@Observable
final class AppSettings {
    enum Key {
        static let peeksOnHover = "notch.peeksOnHover"
        static let collapsesWhenPointerExits = "notch.collapsesWhenPointerExits"
        static let peeksForAttention = "notch.peeksForAttention"
        static let displayPreference = "notch.displayPreference"
        static let timersEnabled = "features.timers.enabled"
        static let keepAwakeEnabled = "features.keepAwake.enabled"
        static let systemMetricsEnabled = "features.systemMetrics.enabled"
        static let audioEnabled = "features.audio.enabled"
        static let quickActionsEnabled = "features.quickActions.enabled"
        static let scrollAdjustsVolume = "audio.scrollAdjustsVolume"
        static let timerPlaysSound = "timers.playsSound"
        static let musicEnabled = "features.music.enabled"
        static let calendarEnabled = "features.calendar.enabled"
        static let calendarLookAheadHours = "calendar.lookAheadHours"
        static let calendarNotchLeadMinutes = "calendar.notchLeadMinutes"
        static let calendarExcludedIDs = "calendar.excludedCalendarIDs"
    }

    static let calendarLookAheadOptions = [3, 6, 12, 24]
    static let calendarNotchLeadOptions = [5, 10, 15, 30]

    var peeksOnHover: Bool {
        didSet { defaults.set(peeksOnHover, forKey: Key.peeksOnHover) }
    }

    var collapsesWhenPointerExits: Bool {
        didSet { defaults.set(collapsesWhenPointerExits, forKey: Key.collapsesWhenPointerExits) }
    }

    var peeksForAttention: Bool {
        didSet { defaults.set(peeksForAttention, forKey: Key.peeksForAttention) }
    }

    var displayPreference: DisplayPreference {
        didSet { defaults.set(displayPreference.rawValue, forKey: Key.displayPreference) }
    }

    // MARK: Features

    var timersEnabled: Bool {
        didSet { defaults.set(timersEnabled, forKey: Key.timersEnabled) }
    }

    var keepAwakeEnabled: Bool {
        didSet { defaults.set(keepAwakeEnabled, forKey: Key.keepAwakeEnabled) }
    }

    var systemMetricsEnabled: Bool {
        didSet { defaults.set(systemMetricsEnabled, forKey: Key.systemMetricsEnabled) }
    }

    var audioEnabled: Bool {
        didSet { defaults.set(audioEnabled, forKey: Key.audioEnabled) }
    }

    var quickActionsEnabled: Bool {
        didSet { defaults.set(quickActionsEnabled, forKey: Key.quickActionsEnabled) }
    }

    var musicEnabled: Bool {
        didSet { defaults.set(musicEnabled, forKey: Key.musicEnabled) }
    }

    /// Off by default: turning it on is what asks for calendar access.
    var calendarEnabled: Bool {
        didSet { defaults.set(calendarEnabled, forKey: Key.calendarEnabled) }
    }

    /// How many hours ahead the command-center schedule looks.
    var calendarLookAheadHours: Int {
        didSet { defaults.set(calendarLookAheadHours, forKey: Key.calendarLookAheadHours) }
    }

    /// How many minutes before it starts a meeting takes the notch.
    var calendarNotchLeadMinutes: Int {
        didSet { defaults.set(calendarNotchLeadMinutes, forKey: Key.calendarNotchLeadMinutes) }
    }

    /// Calendars the user turned off. Stored as exclusions so new calendars show up automatically.
    var calendarExcludedIDs: Set<String> {
        didSet { defaults.set(calendarExcludedIDs.sorted(), forKey: Key.calendarExcludedIDs) }
    }

    /// Scrolling over the notch changes the output volume. Off by default: it is easy to trigger by accident.
    var scrollAdjustsVolume: Bool {
        didSet { defaults.set(scrollAdjustsVolume, forKey: Key.scrollAdjustsVolume) }
    }

    var timerPlaysSound: Bool {
        didSet { defaults.set(timerPlaysSound, forKey: Key.timerPlaysSound) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        peeksOnHover = Self.bool(Key.peeksOnHover, in: defaults, default: true)
        collapsesWhenPointerExits = Self.bool(Key.collapsesWhenPointerExits, in: defaults, default: true)
        peeksForAttention = Self.bool(Key.peeksForAttention, in: defaults, default: true)
        displayPreference = defaults.string(forKey: Key.displayPreference)
            .flatMap(DisplayPreference.init(rawValue:)) ?? .automatic
        timersEnabled = Self.bool(Key.timersEnabled, in: defaults, default: true)
        keepAwakeEnabled = Self.bool(Key.keepAwakeEnabled, in: defaults, default: true)
        systemMetricsEnabled = Self.bool(Key.systemMetricsEnabled, in: defaults, default: true)
        audioEnabled = Self.bool(Key.audioEnabled, in: defaults, default: true)
        quickActionsEnabled = Self.bool(Key.quickActionsEnabled, in: defaults, default: true)
        scrollAdjustsVolume = Self.bool(Key.scrollAdjustsVolume, in: defaults, default: false)
        timerPlaysSound = Self.bool(Key.timerPlaysSound, in: defaults, default: true)
        musicEnabled = Self.bool(Key.musicEnabled, in: defaults, default: true)
        calendarEnabled = Self.bool(Key.calendarEnabled, in: defaults, default: false)
        calendarLookAheadHours = Self.option(Key.calendarLookAheadHours, in: defaults, from: Self.calendarLookAheadOptions, default: 12)
        calendarNotchLeadMinutes = Self.option(Key.calendarNotchLeadMinutes, in: defaults, from: Self.calendarNotchLeadOptions, default: 15)
        calendarExcludedIDs = Set(defaults.stringArray(forKey: Key.calendarExcludedIDs) ?? [])
    }

    /// Reads a stored choice, falling back to the default when it isn't one of the options.
    private static func option(_ key: String, in defaults: UserDefaults, from options: [Int], default defaultValue: Int) -> Int {
        let value = defaults.integer(forKey: key)
        return options.contains(value) ? value : defaultValue
    }

    /// Reads a stored Bool, accepting launch-argument strings such as `-features.audio.enabled NO`.
    private static func bool(_ key: String, in defaults: UserDefaults, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }

    func isEnabled(_ feature: Feature) -> Bool {
        switch feature {
        case .timers: timersEnabled
        case .keepAwake: keepAwakeEnabled
        case .systemMetrics: systemMetricsEnabled
        case .audio: audioEnabled
        case .quickActions: quickActionsEnabled
        case .music: musicEnabled
        case .calendar: calendarEnabled
        }
    }

    /// The calendar options, in the form the calendar feature uses.
    var calendarConfiguration: CalendarProvider.Configuration {
        CalendarProvider.Configuration(
            lookAhead: TimeInterval(calendarLookAheadHours) * 3600,
            rules: CalendarRules(notchLeadTime: TimeInterval(calendarNotchLeadMinutes) * 60),
            excludedCalendarIDs: calendarExcludedIDs
        )
    }

    /// The subset of settings the notch state machine depends on.
    var stateMachineConfiguration: NotchStateMachine.Configuration {
        NotchStateMachine.Configuration(
            peeksOnHover: peeksOnHover,
            collapsesWhenPointerExits: collapsesWhenPointerExits,
            peeksForAttention: peeksForAttention
        )
    }
}
