import Foundation

/// A tab in the expanded command center.
enum CommandCenterSection: Hashable, Sendable {
    /// Everything, ordered by priority.
    case overview
    /// Only activities of one kind.
    case kind(ActivityKind)

    var symbolName: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .kind(let kind): kind.sectionSymbolName
        }
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .kind(let kind): kind.sectionTitle
        }
    }
}

extension ActivityKind {
    /// Order of kind tabs in the command center.
    static let sectionOrder: [ActivityKind] = [.music, .meeting, .timer, .shelf, .clipboard, .fileTransfer, .agent, .system, .quickActions, .generic]

    var sectionSymbolName: String {
        switch self {
        case .music: "waveform"
        case .meeting: "calendar"
        case .timer: "timer"
        case .shelf: "tray.full"
        case .fileTransfer: "arrow.down.circle"
        case .agent: "terminal"
        case .clipboard: "doc.on.clipboard"
        case .system: "cpu"
        case .quickActions: "bolt"
        case .generic: "circle.grid.2x2"
        }
    }

    var sectionTitle: String {
        switch self {
        case .music: "Now Playing"
        case .meeting: "Calendar"
        case .timer: "Timers"
        case .shelf: "Shelf"
        case .fileTransfer: "Transfers"
        case .agent: "Agents"
        case .clipboard: "Clipboard"
        case .system: "System"
        case .quickActions: "Quick Actions"
        case .generic: "Other"
        }
    }
}

/// What the expanded command center shows: its tabs, the featured (large) activity and the
/// widget column. Derived purely from the engine's resolution, so it is unit tested.
struct CommandCenterLayout: Equatable {
    /// Maximum rows in the widget column before collapsing into a "+N more" line.
    static let maxWidgetRows = 4

    var sections: [CommandCenterSection]
    var selectedSection: CommandCenterSection
    /// Sections containing an activity that requests attention (shown with a badge).
    var attentionSections: Set<CommandCenterSection>
    var featured: NotchActivity?
    var widgets: [NotchActivity]
    var hiddenWidgetCount: Int

    /// Whether the tab row is worth showing (there is more than the overview).
    var showsTabs: Bool { sections.count > 1 }

    static func make(resolution: ActivityResolution, selected: CommandCenterSection) -> CommandCenterLayout {
        let all = resolution.all
        let kinds = ActivityKind.sectionOrder.filter { kind in all.contains { $0.kind == kind } }
        let sections = [CommandCenterSection.overview] + kinds.map(CommandCenterSection.kind)
        let selection = sections.contains(selected) ? selected : .overview

        let visible: [NotchActivity] = switch selection {
        case .overview: all
        case .kind(let kind): all.filter { $0.kind == kind }
        }

        var attention = Set<CommandCenterSection>()
        for activity in all where activity.priority.requestsAttention {
            attention.insert(.kind(activity.kind))
        }

        let rest = Array(visible.dropFirst())
        return CommandCenterLayout(
            sections: sections,
            selectedSection: selection,
            attentionSections: attention,
            featured: visible.first,
            widgets: Array(rest.prefix(maxWidgetRows)),
            hiddenWidgetCount: max(rest.count - maxWidgetRows, 0)
        )
    }
}
