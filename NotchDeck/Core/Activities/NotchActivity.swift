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

/// How an activity should be drawn. Purely descriptive; providers never touch views.
struct ActivityPresentation: Equatable, Sendable {
    /// SF Symbol shown on the leading side of the notch and in lists.
    var symbolName: String
    var accent: ActivityAccent
    var compactAccessory: CompactAccessory?

    init(symbolName: String, accent: ActivityAccent = .neutral, compactAccessory: CompactAccessory? = nil) {
        self.symbolName = symbolName
        self.accent = accent
        self.compactAccessory = compactAccessory
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
