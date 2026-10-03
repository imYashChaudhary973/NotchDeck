import Foundation

/// A feature-side source of activities (timer, music, calendar, agent bridge…).
///
/// Providers observe something and describe it as `NotchActivity` values through the
/// `ActivityPublisher` they are given. They never create, resize, show or hide notch UI.
@MainActor
protocol ActivityProvider: AnyObject {
    /// The source every activity from this provider is published under.
    var source: ActivitySource { get }

    /// Called once when the provider is registered with the engine.
    /// Begin observing here; keep the publisher to publish and withdraw activities.
    func start(publisher: ActivityPublisher)

    /// Called when the provider is unregistered. Stop observers and release resources.
    /// The engine withdraws the provider's activities automatically.
    func stop()

    /// Called when the user invokes one of the provider's activity actions.
    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID)
}

extension ActivityProvider {
    func stop() {}
    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {}
}

/// A provider's handle into the Activity Engine, scoped to that provider's source.
@MainActor
struct ActivityPublisher {
    let source: ActivitySource
    private weak var engine: ActivityEngine?

    init(source: ActivitySource, engine: ActivityEngine) {
        self.source = source
        self.engine = engine
    }

    /// Publishes a new activity or updates an existing one with the same `id`.
    /// Activities whose `source` does not match this publisher are rejected.
    func publish(_ activity: NotchActivity) {
        guard activity.source == source else {
            assertionFailure("Provider '\(source.rawValue)' tried to publish an activity for '\(activity.source.rawValue)'")
            return
        }
        engine?.publish(activity)
    }

    func withdraw(id: NotchActivity.ID) {
        engine?.withdraw(ActivityKey(source: source, id: id))
    }

    func withdrawAll() {
        engine?.withdrawAll(from: source)
    }

    /// The provider's currently live activity with the given id, if any.
    func activity(id: NotchActivity.ID) -> NotchActivity? {
        engine?.activity(for: ActivityKey(source: source, id: id))
    }
}
