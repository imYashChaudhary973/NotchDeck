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

    init(value: Double, valueText: String? = nil) {
        self.value = min(max(value, 0), 1)
        self.valueText = valueText
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

/// The kind of content an activity carries, which selects how the notch draws it in detail.
enum ActivityContent: Equatable, Sendable {
    case standard
    case media(MediaContent)
    case level(LevelContent)
    case metric(MetricContent)
    case toggle(ToggleContent)
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

    init(
        symbolName: String,
        accent: ActivityAccent = .neutral,
        compactAccessory: CompactAccessory? = nil,
        statusText: String? = nil,
        content: ActivityContent = .standard,
        revealsOnUpdate: Bool = false
    ) {
        self.symbolName = symbolName
        self.accent = accent
        self.compactAccessory = compactAccessory
        self.statusText = statusText
        self.content = content
        self.revealsOnUpdate = revealsOnUpdate
    }
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
