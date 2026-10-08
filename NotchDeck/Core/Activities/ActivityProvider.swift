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

    /// Called when the user sets a continuous control (e.g. drags a level bar) to `value` in `0...1`.
    func adjust(actionID: ActivityAction.ID, to value: Double, on activityID: NotchActivity.ID)

    /// Called when the set of this provider's activities on screen changes (empty when none are).
    /// Use it to do work only while it can be seen, e.g. sample CPU usage only while it is displayed.
    func displayedActivitiesChanged(_ ids: Set<NotchActivity.ID>)

    /// Called when the user scrolls over the notch, with the scroll in normalized steps
    /// (positive = up). Return `true` if the provider handled it; the first provider that does wins.
    func handleNotchScroll(_ delta: Double) -> Bool
}

extension ActivityProvider {
    func stop() {}
    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {}
    func adjust(actionID: ActivityAction.ID, to value: Double, on activityID: NotchActivity.ID) {}
    func displayedActivitiesChanged(_ ids: Set<NotchActivity.ID>) {}
    func handleNotchScroll(_ delta: Double) -> Bool { false }
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
