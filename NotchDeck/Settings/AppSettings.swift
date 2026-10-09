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
    case shelf
    case clipboard

    var title: String {
        switch self {
        case .timers: "Timers"
        case .keepAwake: "Keep Awake"
        case .systemMetrics: "System metrics"
        case .audio: "Audio controls"
        case .quickActions: "Quick actions"
        case .music: "Now Playing"
        case .calendar: "Calendar"
        case .shelf: "File Shelf"
        case .clipboard: "Clipboard history"
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
        static let shelfEnabled = "features.shelf.enabled"
        static let shelfOpensOnApproach = "shelf.opensOnApproach"
        static let shelfItemLifetime = "shelf.itemLifetime"
        static let clipboardEnabled = "features.clipboard.enabled"
        static let clipboardPaused = "clipboard.paused"
        static let clipboardMaxEntries = "clipboard.maxEntries"
        static let clipboardRetentionDays = "clipboard.retentionDays"
        static let clipboardExcludedBundleIDs = "clipboard.excludedBundleIDs"
    }

    static let calendarLookAheadOptions = [3, 6, 12, 24]
    static let calendarNotchLeadOptions = [5, 10, 15, 30]
    static let clipboardMaxEntriesOptions = [25, 50, 100, 200]
    /// Days unpinned clipboard entries are kept; 0 keeps them until the history is full or cleared.
    static let clipboardRetentionDaysOptions = [1, 7, 30, 0]

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

    var shelfEnabled: Bool {
        didSet { defaults.set(shelfEnabled, forKey: Key.shelfEnabled) }
    }

    /// A drag coming near the notch opens the shelf, before it reaches the top edge of the screen.
    var shelfOpensOnApproach: Bool {
        didSet { defaults.set(shelfOpensOnApproach, forKey: Key.shelfOpensOnApproach) }
    }

    /// How long new shelf items are kept unless pinned.
    var shelfItemLifetime: ShelfLifetime {
        didSet { defaults.set(shelfItemLifetime.rawValue, forKey: Key.shelfItemLifetime) }
    }

    /// Off by default: clipboard history keeps what the user copies, which is private.
    var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Key.clipboardEnabled) }
    }

    /// Stops keeping new copies without turning the feature (and its history) off.
    var clipboardPaused: Bool {
        didSet { defaults.set(clipboardPaused, forKey: Key.clipboardPaused) }
    }

    /// Most unpinned entries kept.
    var clipboardMaxEntries: Int {
        didSet { defaults.set(clipboardMaxEntries, forKey: Key.clipboardMaxEntries) }
    }

    /// Days unpinned entries are kept; 0 means until the history is full or cleared.
    var clipboardRetentionDays: Int {
        didSet { defaults.set(clipboardRetentionDays, forKey: Key.clipboardRetentionDays) }
    }

    /// Apps whose copies are never kept, by bundle identifier (password managers are always excluded).
    var clipboardExcludedBundleIDs: Set<String> {
        didSet { defaults.set(clipboardExcludedBundleIDs.sorted(), forKey: Key.clipboardExcludedBundleIDs) }
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
        shelfEnabled = Self.bool(Key.shelfEnabled, in: defaults, default: true)
        shelfOpensOnApproach = Self.bool(Key.shelfOpensOnApproach, in: defaults, default: true)
        shelfItemLifetime = defaults.string(forKey: Key.shelfItemLifetime).flatMap(ShelfLifetime.init(rawValue:)) ?? .oneHour
        clipboardEnabled = Self.bool(Key.clipboardEnabled, in: defaults, default: false)
        clipboardPaused = Self.bool(Key.clipboardPaused, in: defaults, default: false)
        clipboardMaxEntries = Self.option(Key.clipboardMaxEntries, in: defaults, from: Self.clipboardMaxEntriesOptions, default: 50)
        clipboardRetentionDays = defaults.object(forKey: Key.clipboardRetentionDays) == nil
            ? 7
            : Self.option(Key.clipboardRetentionDays, in: defaults, from: Self.clipboardRetentionDaysOptions, default: 7)
        clipboardExcludedBundleIDs = Set(defaults.stringArray(forKey: Key.clipboardExcludedBundleIDs) ?? [])
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
        case .shelf: shelfEnabled
        case .clipboard: clipboardEnabled
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

    /// The clipboard options, in the form the clipboard feature uses.
    var clipboardConfiguration: ClipboardProvider.Configuration {
        ClipboardProvider.Configuration(
            limits: ClipboardHistory.Limits(
                maxEntries: clipboardMaxEntries,
                retention: clipboardRetentionDays > 0 ? TimeInterval(clipboardRetentionDays) * 86_400 : nil
            ),
            excludedBundleIDs: clipboardExcludedBundleIDs,
            isPaused: clipboardPaused
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
