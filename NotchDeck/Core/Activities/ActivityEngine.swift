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

    /// Called after `resolution` changes, with the previous and new values.
    @ObservationIgnored var onResolutionChange: ((_ old: ActivityResolution, _ new: ActivityResolution) -> Void)?

    @ObservationIgnored private var store = ActivityStore()
    @ObservationIgnored private let resolver = ActivityResolver()
    @ObservationIgnored private var providers: [ActivitySource: any ActivityProvider] = [:]
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
        Array(providers.keys)
    }

    /// Registers a provider and starts it. A provider already registered for the same source is replaced.
    func register(_ provider: any ActivityProvider) {
        if providers[provider.source] != nil {
            unregister(provider.source)
        }
        providers[provider.source] = provider
        provider.start(publisher: ActivityPublisher(source: provider.source, engine: self))
    }

    /// Stops a provider and withdraws all of its activities.
    func unregister(_ source: ActivitySource) {
        guard let provider = providers.removeValue(forKey: source) else { return }
        provider.stop()
        withdrawAll(from: source)
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
        providers[key.source]?.perform(actionID: action.id, on: key.id)
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
