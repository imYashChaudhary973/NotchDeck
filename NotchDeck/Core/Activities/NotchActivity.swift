import Foundation

/// Identifies the provider that owns an activity, for example `timer` or `calendar`.
struct ActivitySource: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Uniquely identifies an activity across all providers.
struct ActivityKey: Hashable, Sendable {
    let source: ActivitySource
    let id: String
}

/// The broad category of an activity. Used for presentation defaults and, later, profiles.
enum ActivityKind: String, Sendable, CaseIterable {
    case music
    case meeting
    case timer
    case fileTransfer
    case agent
    case clipboard
    case system
    case quickActions
    case generic
}

/// Semantic tint for an activity's glyph. Mapped to concrete colors by the UI layer.
enum ActivityAccent: String, Sendable, CaseIterable {
    case neutral
    case blue
    case green
    case orange
    case red
    case purple
    case pink
    case yellow
}

/// Optional content shown on the trailing side of the notch in the compact Live Activity.
enum CompactAccessory: Equatable, Sendable {
    /// A short piece of text, such as `"12°"`.
    case text(String)
    /// An SF Symbol name.
    case symbol(String)
    /// A live countdown to the given date, rendered by the system without app-side timers.
    case countdown(to: Date)
    /// A progress ring using the activity's `progress`.
    case progress
}

/// A user-invokable action attached to an activity. Routed back to the owning provider.
struct ActivityAction: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var systemImage: String?
    var isDestructive: Bool

    init(id: String, title: String, systemImage: String? = nil, isDestructive: Bool = false) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
    }
}

/// Now Playing information for media activities.
struct MediaContent: Equatable, Sendable {
    var isPlaying: Bool
    /// Playback position at `positionDate`.
    var position: TimeInterval
    var positionDate: Date
    var duration: TimeInterval?
    /// Encoded artwork image (PNG/JPEG). When nil, `artworkSymbol` is drawn on a gradient.
    var artwork: Data?
    var artworkSymbol: String
    /// Identifies the track, so the notch can animate track changes. Nil when unknown.
    var trackID: String?
    /// Action IDs routed to the provider for the transport buttons. Nil hides the button.
    var previousActionID: ActivityAction.ID?
    var playPauseActionID: ActivityAction.ID?
    var nextActionID: ActivityAction.ID?

    init(
        isPlaying: Bool,
        position: TimeInterval = 0,
        positionDate: Date = .now,
        duration: TimeInterval? = nil,
        artwork: Data? = nil,
        artworkSymbol: String = "music.note",
        trackID: String? = nil,
        previousActionID: ActivityAction.ID? = nil,
        playPauseActionID: ActivityAction.ID? = nil,
        nextActionID: ActivityAction.ID? = nil
    ) {
        self.isPlaying = isPlaying
        self.position = position
        self.positionDate = positionDate
        self.duration = duration
        self.artwork = artwork
        self.artworkSymbol = artworkSymbol
        self.trackID = trackID
        self.previousActionID = previousActionID
        self.playPauseActionID = playPauseActionID
        self.nextActionID = nextActionID
    }

    /// The playback position at `date`, extrapolated while playing and clamped to the duration.
    func position(at date: Date) -> TimeInterval {
        let elapsed = isPlaying ? max(date.timeIntervalSince(positionDate), 0) : 0
        let value = max(position + elapsed, 0)
        return duration.map { min(value, $0) } ?? value
    }
}

/// A 0…1 level shown as a segmented bar, such as output volume.
struct LevelContent: Equatable, Sendable {
    var value: Double
    var valueText: String?
    /// When set, the bar is draggable in the command center; new values are routed to the
    /// provider through `ActivityProvider.adjust(actionID:to:on:)`.
    var adjustActionID: ActivityAction.ID?
    /// When set, a mute button is shown; tapping it invokes this action.
    var muteActionID: ActivityAction.ID?
    var isMuted: Bool

    init(
        value: Double,
        valueText: String? = nil,
        adjustActionID: ActivityAction.ID? = nil,
        muteActionID: ActivityAction.ID? = nil,
        isMuted: Bool = false
    ) {
        self.value = min(max(value, 0), 1)
        self.valueText = valueText
        self.adjustActionID = adjustActionID
        self.muteActionID = muteActionID
        self.isMuted = isMuted
    }
}

/// A 0…1 measurement shown as a small bar with a value, such as CPU usage.
struct MetricContent: Equatable, Sendable {
    var value: Double
    var valueText: String

    init(value: Double, valueText: String) {
        self.value = min(max(value, 0), 1)
        self.valueText = valueText
    }
}

/// An on/off control, such as Keep Awake. Toggling invokes `actionID` on the provider.
struct ToggleContent: Equatable, Sendable {
    var isOn: Bool
    var actionID: ActivityAction.ID
    var stateText: String?

    init(isOn: Bool, actionID: ActivityAction.ID, stateText: String? = nil) {
        self.isOn = isOn
        self.actionID = actionID
        self.stateText = stateText
    }
}

/// One button in an `ActionsContent` grid, such as a quick action or a timer preset.
struct ActionItem: Identifiable, Equatable, Sendable {
    /// The action ID routed to the provider when the item is tapped.
    let actionID: ActivityAction.ID
    var title: String
    /// Very short label for the compact button row (e.g. "5m"). When nil, the symbol is shown.
    var compactTitle: String?
    var symbolName: String
    /// Highlights the item, e.g. a quick action whose feature is currently on.
    var isActive: Bool

    var id: ActivityAction.ID { actionID }

    init(actionID: ActivityAction.ID, title: String, compactTitle: String? = nil, symbolName: String, isActive: Bool = false) {
        self.actionID = actionID
        self.title = title
        self.compactTitle = compactTitle
        self.symbolName = symbolName
        self.isActive = isActive
    }
}

/// A set of buttons: a tile grid on the featured card, a row of small buttons in the widget column.
struct ActionsContent: Equatable, Sendable {
    var items: [ActionItem]
}

/// A short list of timed entries, such as the rest of today's meetings.
struct ScheduleContent: Equatable, Sendable {
    struct Entry: Identifiable, Equatable, Sendable {
        let id: String
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var accent: ActivityAccent
        /// Whether the entry is happening now.
        var isNow: Bool
        /// When set, a Join button invokes this action.
        var joinActionID: ActivityAction.ID?

        init(
            id: String,
            title: String,
            start: Date,
            end: Date,
            isAllDay: Bool = false,
            accent: ActivityAccent = .blue,
            isNow: Bool = false,
            joinActionID: ActivityAction.ID? = nil
        ) {
            self.id = id
            self.title = title
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
            self.accent = accent
            self.isNow = isNow
            self.joinActionID = joinActionID
        }
    }

    var entries: [Entry]
}

/// The kind of content an activity carries, which selects how the notch draws it in detail.
enum ActivityContent: Equatable, Sendable {
    case standard
    case media(MediaContent)
    case level(LevelContent)
    case metric(MetricContent)
    case toggle(ToggleContent)
    case actions(ActionsContent)
    case schedule(ScheduleContent)
}

/// A choice among a few options, such as the audio output device. Shown as a list on the
/// featured card; choosing an option invokes its action ID.
struct ActivityOptions: Equatable, Sendable {
    struct Option: Identifiable, Equatable, Sendable {
        let actionID: ActivityAction.ID
        var title: String
        var symbolName: String
        var isSelected: Bool

        var id: ActivityAction.ID { actionID }

        init(actionID: ActivityAction.ID, title: String, symbolName: String, isSelected: Bool = false) {
            self.actionID = actionID
            self.title = title
            self.symbolName = symbolName
            self.isSelected = isSelected
        }
    }

    var title: String
    var options: [Option]
}

/// How an activity should be drawn. Purely descriptive; providers never touch views.
struct ActivityPresentation: Equatable, Sendable {
    /// SF Symbol shown on the leading side of the notch and in lists.
    var symbolName: String
    var accent: ActivityAccent
    var compactAccessory: CompactAccessory?
    /// Short status shown beside the notch in Peek (e.g. "Needs approval"); too long for the compact ears.
    var statusText: String?
    var content: ActivityContent
    /// Briefly reveal (peek) the notch whenever this activity becomes primary or is updated
    /// while primary, regardless of priority. Used for HUD-style activities such as volume.
    var revealsOnUpdate: Bool
    /// An optional choice shown on the featured card, such as the audio output device.
    var options: ActivityOptions?

    init(
        symbolName: String,
        accent: ActivityAccent = .neutral,
        compactAccessory: CompactAccessory? = nil,
        statusText: String? = nil,
        content: ActivityContent = .standard,
        revealsOnUpdate: Bool = false,
        options: ActivityOptions? = nil
    ) {
        self.symbolName = symbolName
        self.accent = accent
        self.compactAccessory = compactAccessory
        self.statusText = statusText
        self.content = content
        self.revealsOnUpdate = revealsOnUpdate
        self.options = options
    }
}

/// Where an activity may appear.
enum ActivityPlacement: Sendable {
    /// Competes for the notch: can become primary and show as a Live Activity or Peek.
    case notch
    /// Listed only in the expanded command center (controls and background context such as
    /// CPU usage or quick actions). Never becomes primary, so it never keeps the notch open.
    case commandCenter
}

/// A description of one thing that is happening, published by a provider.
///
/// Providers publish activities; the Activity Engine decides whether and how they are shown.
/// Publishing an activity with an existing `key` updates it in place.
struct NotchActivity: Identifiable, Equatable, Sendable {
    /// Provider-scoped identifier. Stable across updates of the same activity.
    let id: String
    let source: ActivitySource
    var kind: ActivityKind
    var priority: ActivityPriority
    var placement: ActivityPlacement

    var title: String
    var subtitle: String?

    var startedAt: Date
    /// When set, the engine removes the activity automatically at this time.
    var expiresAt: Date?

    /// Completion fraction in `0...1`, if the activity has measurable progress.
    var progress: Double?

    var presentation: ActivityPresentation
    var actions: [ActivityAction]

    init(
        id: String,
        source: ActivitySource,
        kind: ActivityKind,
        priority: ActivityPriority,
        placement: ActivityPlacement = .notch,
        title: String,
        subtitle: String? = nil,
        startedAt: Date = .now,
        expiresAt: Date? = nil,
        progress: Double? = nil,
        presentation: ActivityPresentation,
        actions: [ActivityAction] = []
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.priority = priority
        self.placement = placement
        self.title = title
        self.subtitle = subtitle
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.progress = progress.map { min(max($0, 0), 1) }
        self.presentation = presentation
        self.actions = actions
    }

    var key: ActivityKey {
        ActivityKey(source: source, id: id)
    }

    func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date
    }
}
