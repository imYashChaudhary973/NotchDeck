#if DEBUG
import Foundation

/// Developer-only provider that publishes fake activities so every notch state and
/// priority interaction can be exercised before real integrations exist.
///
/// It is also the reference example of an `ActivityProvider`: it only publishes and
/// withdraws activities and never touches notch UI.
@MainActor
final class DebugActivityProvider: ActivityProvider {
    let source = ActivitySource(rawValue: "debug")

    private var publisher: ActivityPublisher?
    private var tasks: [String: Task<Void, Never>] = [:]
    private var isMusicPlaying = true

    private enum ActionID {
        static let dismiss = "dismiss"
        static let togglePlayback = "togglePlayback"
        static let complete = "complete"
    }

    private static let dismissAction = ActivityAction(id: ActionID.dismiss, title: "Dismiss", systemImage: "xmark")

    // MARK: ActivityProvider

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
    }

    func stop() {
        cancelAllTasks()
        publisher = nil
    }

    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
        switch actionID {
        case ActionID.togglePlayback:
            isMusicPlaying.toggle()
            simulateMusic(resetPlayback: false)
        default:
            withdraw(activityID)
        }
    }

    // MARK: Simulations

    func simulateMusic(resetPlayback: Bool = true) {
        if resetPlayback { isMusicPlaying = true }
        publish(NotchActivity(
            id: "music",
            source: source,
            kind: .music,
            priority: .passive,
            title: "Midnight City",
            subtitle: isMusicPlaying ? "M83" : "M83 · Paused",
            presentation: ActivityPresentation(
                symbolName: "music.note",
                accent: .pink,
                compactAccessory: .symbol(isMusicPlaying ? "waveform" : "pause.fill")
            ),
            actions: [
                ActivityAction(
                    id: ActionID.togglePlayback,
                    title: isMusicPlaying ? "Pause" : "Play",
                    systemImage: isMusicPlaying ? "pause.fill" : "play.fill"
                ),
                Self.dismissAction,
            ]
        ))
    }

    /// A meeting starting in `startsIn` seconds. Escalates to Attention Required when it starts,
    /// then expires shortly after so whatever it interrupted is restored.
    func simulateMeeting(startsIn: TimeInterval = 60) {
        let id = "meeting"
        let start = Date.now.addingTimeInterval(startsIn)
        let base = NotchActivity(
            id: id,
            source: source,
            kind: .meeting,
            priority: .timeSensitive,
            title: "Design Review",
            subtitle: "Starts at \(start.formatted(date: .omitted, time: .shortened))",
            expiresAt: start.addingTimeInterval(20),
            presentation: ActivityPresentation(symbolName: "calendar", accent: .blue, compactAccessory: .countdown(to: start)),
            actions: [ActivityAction(id: ActionID.complete, title: "Join", systemImage: "video.fill"), Self.dismissAction]
        )
        publish(base)

        run(id) { provider in
            try await Task.sleep(for: .seconds(startsIn))
            var starting = base
            starting.priority = .attentionRequired
            starting.subtitle = "Starting now"
            starting.presentation.compactAccessory = .symbol("video.fill")
            provider.publish(starting)
        }
    }

    /// A countdown timer that escalates near the end and announces completion.
    func simulateTimer(duration: TimeInterval = 30) {
        let id = "timer"
        let end = Date.now.addingTimeInterval(duration)
        var timer = NotchActivity(
            id: id,
            source: source,
            kind: .timer,
            priority: .active,
            title: "Focus Timer",
            subtitle: "\(Int(duration)) seconds",
            presentation: ActivityPresentation(symbolName: "timer", accent: .orange, compactAccessory: .countdown(to: end)),
            actions: [ActivityAction(id: ActionID.dismiss, title: "Cancel", systemImage: "xmark")]
        )
        publish(timer)

        run(id) { provider in
            let escalateAt = max(duration - 10, 0)
            try await Task.sleep(for: .seconds(escalateAt))
            timer.priority = .timeSensitive
            provider.publish(timer)

            try await Task.sleep(for: .seconds(duration - escalateAt))
            provider.publish(NotchActivity(
                id: id,
                source: provider.source,
                kind: .timer,
                priority: .attentionRequired,
                title: "Timer finished",
                subtitle: "Focus Timer",
                expiresAt: .now.addingTimeInterval(6),
                presentation: ActivityPresentation(symbolName: "bell.fill", accent: .orange, compactAccessory: .symbol("checkmark")),
                actions: [Self.dismissAction]
            ))
        }
    }

    /// A download whose progress advances over `duration` seconds.
    func simulateFileTransfer(duration: TimeInterval = 12) {
        let id = "transfer"
        let steps = 24
        var transfer = NotchActivity(
            id: id,
            source: source,
            kind: .fileTransfer,
            priority: .active,
            title: "Downloading Xcode.xip",
            subtitle: "0%",
            progress: 0,
            presentation: ActivityPresentation(symbolName: "arrow.down.circle.fill", accent: .green, compactAccessory: .progress),
            actions: [ActivityAction(id: ActionID.dismiss, title: "Cancel", systemImage: "xmark")]
        )
        publish(transfer)

        run(id) { provider in
            for step in 1...steps {
                try await Task.sleep(for: .seconds(duration / Double(steps)))
                let fraction = Double(step) / Double(steps)
                transfer.progress = fraction
                transfer.subtitle = fraction.formatted(.percent.precision(.fractionLength(0)))
                provider.publish(transfer)
            }
            transfer.title = "Download complete"
            transfer.subtitle = "Xcode.xip"
            transfer.priority = .passive
            transfer.expiresAt = .now.addingTimeInterval(4)
            transfer.presentation.compactAccessory = .symbol("checkmark")
            transfer.actions = []
            provider.publish(transfer)
        }
    }

    func simulateAgentAttention() {
        publish(NotchActivity(
            id: "agent",
            source: source,
            kind: .agent,
            priority: .attentionRequired,
            title: "Claude needs you",
            subtitle: "Permission required · Rove",
            presentation: ActivityPresentation(
                symbolName: "exclamationmark.bubble.fill",
                accent: .orange,
                compactAccessory: .symbol("hand.raised.fill")
            ),
            actions: [ActivityAction(id: ActionID.complete, title: "Open", systemImage: "terminal"), Self.dismissAction]
        ))
    }

    /// A short-lived clipboard confirmation. Deliberately describes the copy without including its contents.
    func simulateClipboard() {
        publish(NotchActivity(
            id: "clipboard",
            source: source,
            kind: .clipboard,
            priority: .passive,
            title: "Copied",
            subtitle: "Text · 42 characters",
            expiresAt: .now.addingTimeInterval(5),
            presentation: ActivityPresentation(symbolName: "doc.on.clipboard", accent: .neutral, compactAccessory: .symbol("checkmark"))
        ))
    }

    func simulateCritical() {
        publish(NotchActivity(
            id: "critical",
            source: source,
            kind: .system,
            priority: .critical,
            title: "Critical alert",
            subtitle: "Simulated · expires in 8 s",
            expiresAt: .now.addingTimeInterval(8),
            presentation: ActivityPresentation(symbolName: "exclamationmark.triangle.fill", accent: .red, compactAccessory: .symbol("exclamationmark")),
            actions: [Self.dismissAction]
        ))
    }

    func withdraw(_ id: NotchActivity.ID) {
        tasks.removeValue(forKey: id)?.cancel()
        publisher?.withdraw(id: id)
    }

    func clearAll() {
        cancelAllTasks()
        publisher?.withdrawAll()
    }

    // MARK: Helpers

    private func publish(_ activity: NotchActivity) {
        publisher?.publish(activity)
    }

    /// Runs a scripted sequence for one activity, replacing any sequence already running for it.
    private func run(_ id: String, _ script: @escaping @MainActor (DebugActivityProvider) async throws -> Void) {
        tasks.removeValue(forKey: id)?.cancel()
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                try await script(self)
            } catch {
                // Cancelled: the activity was dismissed or re-simulated.
            }
            if !Task.isCancelled {
                self.tasks[id] = nil
            }
        }
    }

    private func cancelAllTasks() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
#endif
