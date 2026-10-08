import Foundation

/// The Quick Actions grid in the command center. Shows only actions that are available.
@MainActor
final class QuickActionsProvider: ActivityProvider {
    let source = ActivitySource(rawValue: "quickActions")
    static let activityID = "quickActions"

    private let actions: [any QuickAction]
    private var publisher: ActivityPublisher?

    init(actions: [any QuickAction]) {
        self.actions = actions
    }

    var availableActions: [any QuickAction] {
        actions.filter { $0.availability == .available }
    }

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
        refresh()
    }

    func stop() {
        publisher = nil
    }

    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
        guard let action = availableActions.first(where: { $0.id == actionID }) else { return }
        action.perform()
        // The action may have changed what is available or active (e.g. Keep Awake).
        refresh()
    }

    /// Republishes the grid. Call when an action's availability or active state may have changed.
    func refresh() {
        guard let publisher else { return }
        let items = availableActions.map {
            ActionItem(actionID: $0.id, title: $0.title, symbolName: $0.symbolName, isActive: $0.isActive)
        }
        if items.isEmpty {
            publisher.withdraw(id: Self.activityID)
        } else {
            publisher.publish(Self.activity(items: items, source: source))
        }
    }

    static func activity(items: [ActionItem], source: ActivitySource) -> NotchActivity {
        NotchActivity(
            id: activityID,
            source: source,
            kind: .quickActions,
            // Command-center activities never take the notch; priority only orders the list.
            // Above the system rows, so the grid is the featured card when nothing is happening.
            priority: .passive,
            placement: .commandCenter,
            title: "Quick Actions",
            presentation: ActivityPresentation(
                symbolName: "bolt.fill",
                accent: .yellow,
                content: .actions(ActionsContent(items: items))
            )
        )
    }
}
