import Foundation

/// Countdown timers: presets, custom durations, pause/resume/cancel, escalation near zero and a
/// completion alert.
///
/// Several timers can run at once, but only the most relevant one competes for the notch; the
/// others are listed in the command center. Nothing ticks: the countdown is drawn by the system,
/// and the provider wakes only at the next phase change (one minute left, ten seconds left,
/// finished, alert over). Timers are persisted, so they survive a relaunch.
@MainActor
final class TimerProvider: ActivityProvider {
    let source = ActivitySource(rawValue: "timer")

    /// Called when a timer reaches zero (plays the completion sound).
    var onFinish: ((CountdownTimer) -> Void)?
    /// Called when the user picks "Custom" (opens the custom duration window).
    var onRequestCustomDuration: (() -> Void)?

    private(set) var collection = TimerCollection()

    private var publisher: ActivityPublisher?
    private var publishedIDs: Set<NotchActivity.ID> = []
    private var transitionTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let schedulesTransitions: Bool

    static let persistenceKey = "timers.saved"
    static let presetsActivityID = "presets"

    enum ActionID {
        static let pause = "pause"
        static let resume = "resume"
        static let cancel = "cancel"
        static let addMinute = "addMinute"
        static let restart = "restart"
        static let dismiss = "dismiss"
        static let custom = "custom"
        static let presetPrefix = "preset-"

        static func preset(_ duration: TimeInterval) -> String {
            presetPrefix + String(Int(duration))
        }
    }

    /// - Parameters:
    ///   - now: Clock, injectable for tests.
    ///   - schedulesTransitions: When `false`, phase changes only happen when `advance()` is called.
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { .now }, schedulesTransitions: Bool = true) {
        self.defaults = defaults
        self.now = now
        self.schedulesTransitions = schedulesTransitions
    }

    // MARK: ActivityProvider

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
        collection = Self.load(from: defaults)
        // Timers that ended while NotchDeck wasn't running are dropped quietly.
        collection.advance(to: now())
        changed(announcing: [])
    }

    func stop() {
        transitionTask?.cancel()
        transitionTask = nil
        publisher = nil
        publishedIDs.removeAll()
    }

    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
        if activityID == Self.presetsActivityID {
            if actionID == ActionID.custom {
                onRequestCustomDuration?()
            } else if actionID.hasPrefix(ActionID.presetPrefix),
                      let seconds = TimeInterval(actionID.dropFirst(ActionID.presetPrefix.count)) {
                startTimer(duration: seconds)
            }
            return
        }

        guard let id = Self.timerID(from: activityID) else { return }
        let date = now()
        switch actionID {
        case ActionID.pause: collection.pause(id, now: date)
        case ActionID.resume: collection.resume(id, now: date)
        case ActionID.addMinute: collection.addTime(TimerRules.addedTime, to: id, now: date)
        case ActionID.restart: collection.restart(id, now: date)
        case ActionID.cancel, ActionID.dismiss: collection.remove(id)
        default: return
        }
        changed(announcing: [])
    }

    // MARK: Commands

    /// Starts a new timer. Durations are clamped to 1 second … 24 hours.
    @discardableResult
    func startTimer(duration: TimeInterval, label: String? = nil) -> UUID {
        let id = collection.start(duration: duration, label: label, now: now())
        changed(announcing: [])
        return id
    }

    /// Cancels every timer (used when the feature is turned off).
    func cancelAll() {
        collection.removeAll()
        changed(announcing: [])
    }

    /// Applies phase changes due by now. Called by the scheduled wake-up, or directly in tests.
    func advance() {
        let finished = collection.advance(to: now())
        changed(announcing: finished)
    }

    // MARK: Publishing

    private func changed(announcing finished: [CountdownTimer]) {
        save()
        publishAll()
        finished.forEach { onFinish?($0) }
        scheduleNextTransition()
    }

    private func publishAll() {
        guard let publisher else { return }
        let date = now()
        let activities = Self.activities(for: collection, now: date, source: source)
        let ids = Set(activities.map(\.id))
        for stale in publishedIDs.subtracting(ids) {
            publisher.withdraw(id: stale)
        }
        activities.forEach(publisher.publish)
        publishedIDs = ids
    }

    private func scheduleNextTransition() {
        transitionTask?.cancel()
        transitionTask = nil
        guard schedulesTransitions, publisher != nil, let next = collection.nextTransition(after: now()) else { return }
        let delay = max(next.timeIntervalSince(now()), 0)
        transitionTask = Task { [weak self] in
            // Continuous clock: keeps counting across sleep, so timers stay wall-clock accurate.
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(100), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    // MARK: Persistence

    private func save() {
        if collection.isEmpty {
            defaults.removeObject(forKey: Self.persistenceKey)
        } else if let data = try? JSONEncoder().encode(collection) {
            defaults.set(data, forKey: Self.persistenceKey)
        }
    }

    static func load(from defaults: UserDefaults) -> TimerCollection {
        guard let data = defaults.data(forKey: persistenceKey),
              let collection = try? JSONDecoder().decode(TimerCollection.self, from: data) else {
            return TimerCollection()
        }
        return collection
    }

    // MARK: Activities

    static func activityID(for id: UUID) -> NotchActivity.ID {
        "timer-" + id.uuidString
    }

    static func timerID(from activityID: NotchActivity.ID) -> UUID? {
        guard activityID.hasPrefix("timer-") else { return nil }
        return UUID(uuidString: String(activityID.dropFirst("timer-".count)))
    }

    /// Every activity the timer feature shows for `collection` at `now`: one per timer (only the most
    /// relevant may take the notch) plus the presets row for starting a new timer.
    static func activities(for collection: TimerCollection, now: Date, source: ActivitySource) -> [NotchActivity] {
        let relevant = collection.mostRelevant(at: now)
        return collection.timers.map { activity(for: $0, isMostRelevant: $0.id == relevant, now: now, source: source) }
            + [presetsActivity(source: source)]
    }

    static func activity(for timer: CountdownTimer, isMostRelevant: Bool, now: Date, source: ActivitySource) -> NotchActivity {
        let phase = timer.phase(at: now)
        let pause = ActivityAction(id: ActionID.pause, title: "Pause", systemImage: "pause.fill")
        let resume = ActivityAction(id: ActionID.resume, title: "Resume", systemImage: "play.fill")
        let addMinute = ActivityAction(id: ActionID.addMinute, title: "+1 Min", systemImage: "plus")
        let cancel = ActivityAction(id: ActionID.cancel, title: "Cancel", systemImage: "xmark")

        var activity = NotchActivity(
            id: activityID(for: timer.id),
            source: source,
            kind: .timer,
            priority: phase.priority,
            placement: isMostRelevant ? .notch : .commandCenter,
            title: timer.label,
            presentation: ActivityPresentation(symbolName: "timer", accent: phase == .finalSeconds ? .red : .orange)
        )

        switch timer.state {
        case .running(let endsAt):
            activity.subtitle = "Ends at \(endsAt.formatted(date: .omitted, time: .shortened))"
            activity.presentation.compactAccessory = .countdown(to: endsAt)
            activity.actions = [pause, addMinute, cancel]
        case .paused(let remaining):
            activity.subtitle = "Paused · \(TimerRules.clockText(remaining)) left"
            activity.presentation.symbolName = "pause.circle.fill"
            activity.presentation.compactAccessory = .text(TimerRules.clockText(remaining))
            activity.presentation.statusText = "Paused"
            activity.actions = [resume, cancel]
        case .finished(let at):
            activity.subtitle = "Finished at \(at.formatted(date: .omitted, time: .shortened))"
            activity.expiresAt = at.addingTimeInterval(TimerRules.finishedAlertDuration)
            activity.presentation.symbolName = "bell.fill"
            activity.presentation.compactAccessory = .symbol("checkmark")
            activity.presentation.statusText = "Done"
            activity.actions = [
                ActivityAction(id: ActionID.restart, title: "Restart", systemImage: "arrow.clockwise"),
                ActivityAction(id: ActionID.dismiss, title: "Dismiss", systemImage: "xmark"),
            ]
        }
        return activity
    }

    static func presetsActivity(source: ActivitySource) -> NotchActivity {
        let presets = TimerRules.presets.map { duration in
            ActionItem(
                actionID: ActionID.preset(duration),
                title: TimerRules.durationLabel(duration),
                compactTitle: TimerRules.shortDurationLabel(duration),
                symbolName: "timer"
            )
        }
        let custom = ActionItem(actionID: ActionID.custom, title: "Custom…", compactTitle: "…", symbolName: "slider.horizontal.3")
        return NotchActivity(
            id: presetsActivityID,
            source: source,
            kind: .timer,
            priority: .ambient,
            placement: .commandCenter,
            title: "New Timer",
            presentation: ActivityPresentation(
                symbolName: "plus",
                accent: .orange,
                content: .actions(ActionsContent(items: presets + [custom]))
            )
        )
    }
}
