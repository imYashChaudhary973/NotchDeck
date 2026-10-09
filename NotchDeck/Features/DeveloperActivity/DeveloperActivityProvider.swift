import Foundation

/// Coding agents (Claude Code, Codex or any tool that speaks the developer activity protocol):
/// one activity per session, so the notch shows the most important one and the command center's
/// Agents tab lists them all.
///
/// Generic by design: messages arrive from a `DeveloperEventSource` (the local socket `notchctl`
/// talks to) in one tool-neutral format, and nothing here knows a particular tool beyond its display
/// name and symbol. Event-driven: the provider reacts to messages and otherwise wakes only at the
/// next rule boundary (a finished session leaving the notch, a stale session expiring).
@MainActor
final class DeveloperActivityProvider: ActivityProvider {
    let source = ActivitySource(rawValue: "developer")
    static let sessionIDPrefix = "session-"
    /// The command-center row shown when the event source can't start.
    static let bridgeActivityID = "bridge"
    static let bridgePriority = ActivityPriority(rawValue: 18)

    enum ActionID {
        static let openTerminal = "openTerminal"
        static let openWorkspace = "openWorkspace"
        static let dismiss = "dismiss"
        static let retry = "retry"
    }

    private(set) var sessions = DeveloperSessionCollection()
    /// Why the event source couldn't start, while it isn't listening.
    private(set) var bridgeFailure: String?

    private var publisher: ActivityPublisher?
    private var publishedIDs: Set<NotchActivity.ID> = []
    private var wakeTask: Task<Void, Never>?
    private let eventSource: any DeveloperEventSource
    private let workspace: any DeveloperWorkspaceOpening
    private let now: () -> Date
    private let schedulesWakeUps: Bool

    /// - Parameters:
    ///   - source: Delivers messages from developer tools.
    ///   - now: Clock, injectable for tests.
    ///   - schedulesWakeUps: When `false`, time only moves on when `advance()` is called.
    init(
        source: any DeveloperEventSource,
        workspace: any DeveloperWorkspaceOpening = SystemDeveloperWorkspace(),
        now: @escaping () -> Date = { .now },
        schedulesWakeUps: Bool = true
    ) {
        eventSource = source
        self.workspace = workspace
        self.now = now
        self.schedulesWakeUps = schedulesWakeUps
    }

    // MARK: ActivityProvider

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
        startEventSource()
        evaluate()
    }

    func stop() {
        eventSource.stop()
        wakeTask?.cancel()
        wakeTask = nil
        publisher = nil
        publishedIDs.removeAll()
        sessions.removeAll()
        bridgeFailure = nil
    }

    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
        if activityID == Self.bridgeActivityID {
            guard actionID == ActionID.retry else { return }
            eventSource.stop()
            startEventSource()
            evaluate()
            return
        }
        guard let id = Self.sessionID(from: activityID), let session = sessions.session(id: id) else { return }
        switch actionID {
        case ActionID.openTerminal:
            openTerminal(for: session)
        case ActionID.openWorkspace:
            if let directory = DeveloperWorkspaceValidator.directory(atPath: session.workspacePath) {
                workspace.openInFinder(directory)
            }
        case ActionID.dismiss:
            sessions.remove(id: id)
            evaluate()
        default:
            break
        }
    }

    // MARK: Messages

    /// Applies a message from the event source. Also used by the debug panel and tests to inject
    /// messages. Ignored while the provider isn't running.
    func receive(_ message: DeveloperBridgeMessage) {
        guard publisher != nil, message.type != .ping else { return }
        sessions.apply(message, now: now())
        evaluate()
    }

    /// Applies changes due by now. Called by the scheduled wake-up, or directly in tests.
    func advance() {
        evaluate()
    }

    private func startEventSource() {
        do {
            try eventSource.start { [weak self] message in self?.receive(message) }
            bridgeFailure = nil
        } catch {
            bridgeFailure = Self.failureReason(for: error)
        }
    }

    /// The running terminal or editor the session reported, if it's a known app; otherwise a
    /// Terminal window in the session's workspace.
    private func openTerminal(for session: DeveloperActivity) {
        if let bundleID = session.terminalBundleID, DeveloperApps.isKnown(bundleID), workspace.isRunning(bundleIdentifier: bundleID) {
            workspace.activate(bundleIdentifier: bundleID)
        } else if let directory = DeveloperWorkspaceValidator.directory(atPath: session.workspacePath) {
            workspace.openInTerminal(directory)
        }
    }

    // MARK: Publishing

    private func evaluate() {
        guard let publisher else { return }
        let date = now()
        sessions.removeExpired(at: date)
        let activities = Self.activities(for: sessions, bridgeFailure: bridgeFailure, now: date, source: source)
        let ids = Set(activities.map(\.id))
        for stale in publishedIDs.subtracting(ids) {
            publisher.withdraw(id: stale)
        }
        activities.forEach(publisher.publish)
        publishedIDs = ids
        scheduleWakeUp(after: date)
    }

    private func scheduleWakeUp(after date: Date) {
        wakeTask?.cancel()
        wakeTask = nil
        guard schedulesWakeUps, publisher != nil, let next = sessions.nextBoundary(after: date) else { return }
        let delay = max(next.timeIntervalSince(date), 0)
        wakeTask = Task { [weak self] in
            // Continuous clock: keeps counting across sleep.
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(1), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    // MARK: Activities

    static func activityID(for id: DeveloperActivity.ID) -> NotchActivity.ID {
        sessionIDPrefix + id
    }

    static func sessionID(from activityID: NotchActivity.ID) -> DeveloperActivity.ID? {
        guard activityID.hasPrefix(sessionIDPrefix) else { return nil }
        return String(activityID.dropFirst(sessionIDPrefix.count))
    }

    /// Every activity the feature shows at `now`: one per session still shown, plus the bridge row
    /// while the event source isn't listening.
    static func activities(
        for sessions: DeveloperSessionCollection,
        bridgeFailure: String?,
        now: Date,
        source: ActivitySource
    ) -> [NotchActivity] {
        var activities = sessions.sessions.compactMap { session in
            DeveloperActivityRules.phase(for: session, at: now).map { activity(for: session, phase: $0, source: source) }
        }
        if let bridgeFailure {
            activities.append(bridgeActivity(reason: bridgeFailure, source: source))
        }
        return activities
    }

    static func activity(for session: DeveloperActivity, phase: DeveloperSessionPhase, source: ActivitySource) -> NotchActivity {
        let style = DeveloperProviderStyle(integrationID: session.integrationID)
        let status = session.status
        return NotchActivity(
            id: activityID(for: session.id),
            source: source,
            kind: .agent,
            priority: phase.priority,
            placement: phase.placement,
            title: title(for: session),
            subtitle: subtitle(for: session),
            startedAt: session.startedAt,
            // Leaves on its own even if no wake-up runs (e.g. the provider was stopped).
            expiresAt: phase.removesAtEnd ? phase.endsAt : nil,
            progress: session.progress,
            presentation: ActivityPresentation(
                symbolName: style.symbolName,
                accent: status == .failed ? .red : style.accent,
                compactAccessory: compactAccessory(for: session),
                statusText: status.statusText,
                content: .agent(AgentContent(
                    providerName: session.providerName,
                    shortName: session.shortName,
                    project: session.project,
                    task: session.task,
                    message: session.statusMessage,
                    statusText: status.statusText,
                    tone: status.tone,
                    startedAt: session.startedAt,
                    endedAt: session.finishedAt
                ))
            ),
            actions: actions(for: session)
        )
    }

    /// "Claude · Rove" while busy or waiting, "Claude needs you", "Rove finished", "Claude failed",
    /// "Rove cancelled".
    static func title(for session: DeveloperActivity) -> String {
        let name = session.shortName
        switch session.status {
        case .starting, .working, .runningCommand, .waiting:
            return session.project.map { "\(name) · \($0)" } ?? session.providerName
        case .needsInput, .needsPermission:
            return "\(name) needs you"
        case .completed:
            return "\(session.project ?? name) finished"
        case .failed:
            return "\(name) failed"
        case .cancelled:
            return "\(session.project ?? name) cancelled"
        }
    }

    /// The status message, otherwise the task; led by whichever of agent and project the title leaves out.
    static func subtitle(for session: DeveloperActivity) -> String? {
        let detail = session.statusMessage ?? session.task
        let lead: String? = switch session.status {
        case .starting, .working, .runningCommand, .waiting: nil
        case .needsInput, .needsPermission, .failed: session.project
        case .completed, .cancelled: session.project == nil ? nil : session.shortName
        }
        let parts = [lead, detail].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func compactAccessory(for session: DeveloperActivity) -> CompactAccessory {
        switch session.status {
        case .starting, .working, .runningCommand:
            session.progress == nil ? .elapsed(since: session.startedAt) : .progress
        case .waiting:
            session.progress == nil ? .symbol("hourglass") : .progress
        case .needsInput, .needsPermission:
            .symbol("hand.raised.fill")
        case .completed:
            .symbol("checkmark")
        case .failed:
            .symbol("exclamationmark.triangle.fill")
        case .cancelled:
            .symbol("xmark")
        }
    }

    /// Open Terminal (when there is a workspace or a known terminal), Open Workspace (when there is
    /// a workspace) and Dismiss. Paths and apps are validated again when an action runs.
    static func actions(for session: DeveloperActivity) -> [ActivityAction] {
        var actions: [ActivityAction] = []
        let knownTerminal = session.terminalBundleID.map(DeveloperApps.isKnown) ?? false
        if session.workspacePath != nil || knownTerminal {
            actions.append(ActivityAction(id: ActionID.openTerminal, title: "Open Terminal", systemImage: "terminal"))
        }
        if session.workspacePath != nil {
            actions.append(ActivityAction(id: ActionID.openWorkspace, title: "Open Workspace", systemImage: "folder"))
        }
        actions.append(ActivityAction(id: ActionID.dismiss, title: "Dismiss", systemImage: "xmark"))
        return actions
    }

    static func bridgeActivity(reason: String, source: ActivitySource) -> NotchActivity {
        NotchActivity(
            id: bridgeActivityID,
            source: source,
            kind: .agent,
            priority: bridgePriority,
            placement: .commandCenter,
            title: "Developer bridge unavailable",
            subtitle: reason,
            presentation: ActivityPresentation(symbolName: "exclamationmark.triangle", accent: .yellow),
            actions: [ActivityAction(id: ActionID.retry, title: "Retry", systemImage: "arrow.clockwise")]
        )
    }

    /// A short, single-line reason for the bridge row.
    static func failureReason(for error: any Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        return DeveloperBridgeMessage.sanitizedText(text, maxLength: 120) ?? "NotchDeck couldn't listen for developer tools."
    }
}

/// The symbol and accent an integration is drawn with.
struct DeveloperProviderStyle: Equatable, Sendable {
    var symbolName: String
    var accent: ActivityAccent

    init(integrationID: String) {
        switch integrationID {
        case "claude-code":
            symbolName = "asterisk"
            accent = .orange
        case "codex":
            symbolName = "chevron.left.forwardslash.chevron.right"
            accent = .neutral
        default:
            symbolName = "terminal"
            accent = .blue
        }
    }
}
