import Foundation
import Observation

/// Owns all live activities and decides which one is presented.
///
/// Pipeline: providers publish → `ActivityStore` → `ActivityResolver` → `resolution`.
/// The notch layer observes `resolution`; nothing else decides what the notch shows.
///
/// Expiry is event-driven: the engine schedules a single wake-up for the earliest
/// `expiresAt` instead of polling.
@MainActor
@Observable
final class ActivityEngine {
    /// The current resolution. Observed by the notch presentation layer.
    private(set) var resolution: ActivityResolution = .empty

    /// Whether a registered provider accepts content dropped on the notch. Observed by the notch,
    /// which opens its shelf for drags only while this is true.
    private(set) var acceptsDrops = false

    /// Called after `resolution` changes, with the previous and new values.
    @ObservationIgnored var onResolutionChange: ((_ old: ActivityResolution, _ new: ActivityResolution) -> Void)?

    @ObservationIgnored private var store = ActivityStore()
    @ObservationIgnored private let resolver = ActivityResolver()
    @ObservationIgnored private var providers: [ActivitySource: any ActivityProvider] = [:]
    /// Registration order, so scroll routing is deterministic.
    @ObservationIgnored private var providerOrder: [ActivitySource] = []
    /// Activities currently on screen, as last reported by the notch layer.
    @ObservationIgnored private(set) var displayedKeys: Set<ActivityKey> = []
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let schedulesExpiry: Bool
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    /// - Parameters:
    ///   - now: Clock used for expiry decisions. Injectable for tests.
    ///   - schedulesExpiry: When `false`, expiry only happens when `expireActivities()` is called.
    init(now: @escaping () -> Date = { .now }, schedulesExpiry: Bool = true) {
        self.now = now
        self.schedulesExpiry = schedulesExpiry
    }

    // MARK: Providers

    var registeredSources: [ActivitySource] {
        providerOrder
    }

    func isRegistered(_ source: ActivitySource) -> Bool {
        providers[source] != nil
    }

    /// Registers a provider and starts it. A provider already registered for the same source is replaced.
    func register(_ provider: any ActivityProvider) {
        if providers[provider.source] != nil {
            unregister(provider.source)
        }
        providers[provider.source] = provider
        providerOrder.append(provider.source)
        updateAcceptsDrops()
        provider.start(publisher: ActivityPublisher(source: provider.source, engine: self))
        let displayed = displayedIDs(for: provider.source, in: displayedKeys)
        if !displayed.isEmpty {
            provider.displayedActivitiesChanged(displayed)
        }
    }

    /// Stops a provider and withdraws all of its activities.
    func unregister(_ source: ActivitySource) {
        guard let provider = providers.removeValue(forKey: source) else { return }
        providerOrder.removeAll { $0 == source }
        updateAcceptsDrops()
        provider.stop()
        withdrawAll(from: source)
    }

    private func updateAcceptsDrops() {
        let accepts = providers.values.contains { $0.acceptsDrops }
        if accepts != acceptsDrops { acceptsDrops = accepts }
    }

    // MARK: Activities

    func activity(for key: ActivityKey) -> NotchActivity? {
        store.activity(for: key)
    }

    func publish(_ activity: NotchActivity) {
        store.upsert(activity)
        refresh()
    }

    func withdraw(_ key: ActivityKey) {
        guard store.remove(key) != nil else { return }
        refresh()
    }

    func withdrawAll(from source: ActivitySource) {
        guard !store.removeAll(from: source).isEmpty else { return }
        refresh()
    }

    /// Routes a user action to the provider that owns the activity.
    func perform(_ action: ActivityAction, on key: ActivityKey) {
        perform(actionID: action.id, on: key)
    }

    /// Routes a control interaction (transport button, toggle…) to the provider that owns the activity.
    func perform(actionID: ActivityAction.ID, on key: ActivityKey) {
        providers[key.source]?.perform(actionID: actionID, on: key.id)
    }

    /// Routes a continuous control value (e.g. a dragged level bar) to the provider that owns the activity.
    func adjust(actionID: ActivityAction.ID, to value: Double, on key: ActivityKey) {
        providers[key.source]?.adjust(actionID: actionID, to: min(max(value, 0), 1), on: key.id)
    }

    /// Offers a scroll over the notch to providers in registration order. Returns whether one handled it.
    @discardableResult
    func routeNotchScroll(_ delta: Double) -> Bool {
        for source in providerOrder {
            if providers[source]?.handleNotchScroll(delta) == true { return true }
        }
        return false
    }

    /// Offers content dropped on the notch to providers that accept drops, in registration order.
    /// Returns whether one took it.
    @discardableResult
    func routeDrop(_ drop: NotchDrop) -> Bool {
        guard !drop.items.isEmpty else { return false }
        for source in providerOrder {
            guard let provider = providers[source], provider.acceptsDrops else { continue }
            if provider.handleDrop(drop) { return true }
        }
        return false
    }

    /// Records which activities are on screen and tells each provider whose share changed.
    /// Reported by the notch layer; providers use it to avoid work nobody can see.
    func updateDisplayedActivities(_ keys: Set<ActivityKey>) {
        guard keys != displayedKeys else { return }
        let old = displayedKeys
        // Store first: a provider may publish in response, which can report displayed keys again.
        displayedKeys = keys
        let sources = Set(old.map(\.source)).union(keys.map(\.source))
        for source in providerOrder where sources.contains(source) {
            let before = displayedIDs(for: source, in: old)
            let after = displayedIDs(for: source, in: keys)
            if before != after {
                providers[source]?.displayedActivitiesChanged(after)
            }
        }
    }

    private func displayedIDs(for source: ActivitySource, in keys: Set<ActivityKey>) -> Set<NotchActivity.ID> {
        Set(keys.filter { $0.source == source }.map(\.id))
    }

    /// Removes expired activities and re-resolves. Called automatically when expiry is scheduled.
    func expireActivities() {
        refresh()
    }

    // MARK: Resolution

    private func refresh() {
        let date = now()
        store.removeExpired(at: date)

        let old = resolution
        let new = resolver.resolve(store.all, current: old.primary?.key, now: date)
        if new != old {
            resolution = new
            onResolutionChange?(old, new)
        }
        scheduleNextExpiry(after: date)
    }

    private func scheduleNextExpiry(after date: Date) {
        expiryTask?.cancel()
        expiryTask = nil
        guard schedulesExpiry, let next = store.nextExpiry else { return }

        let delay = max(next.timeIntervalSince(date), 0)
        expiryTask = Task { [weak self] in
            // Continuous clock keeps counting across system sleep, so expiry stays wall-clock accurate.
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(250), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.expireActivities()
        }
    }
}
