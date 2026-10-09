import Foundation

/// Display names for integration IDs. Tools NotchDeck knows get proper names; any other tool gets
/// its ID title-cased (`my-tool` → "My Tool") unless it sends its own `providerName`.
enum DeveloperProviderNames {
    /// Full and short names of known integrations.
    static let known: [String: (name: String, shortName: String)] = [
        "claude-code": ("Claude Code", "Claude"),
        "codex": ("Codex", "Codex"),
    ]

    static func name(for integrationID: String) -> String {
        known[integrationID]?.name ?? titleCased(integrationID)
    }

    /// The short name of a known integration, e.g. "Claude"; nil for others.
    static func shortName(for integrationID: String) -> String? {
        known[integrationID]?.shortName
    }

    /// `my-tool` → "My Tool": `-`, `_` and `.` separate words.
    static func titleCased(_ integrationID: String) -> String {
        let words = integrationID
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? integrationID : words.joined(separator: " ")
    }
}

/// One coding agent session as NotchDeck knows it, such as Claude Code working in a project.
///
/// Built from the session's first `event` message and updated by later ones: fields a message
/// carries replace the stored values, and fields it leaves out keep them (a hook that reports only
/// a status keeps the task). When a finished session becomes active again, a new task has begun:
/// `startedAt` resets and the previous task, message and progress are cleared.
struct DeveloperActivity: Identifiable, Equatable, Sendable {
    /// Assigned on first sight; stable for the session's lifetime. Never derived from paths.
    let id: String
    /// Identifies the session in messages (`DeveloperBridgeMessage.sessionKey`).
    let sessionKey: String
    /// The integration ID, e.g. `claude-code`.
    let integrationID: String
    /// The name the tool reported, if any (see `providerName`).
    var reportedProviderName: String?
    /// The project the tool reported, if any (see `project`).
    var reportedProject: String?
    /// Absolute path of the directory the session works in. Untrusted: validated before use.
    var workspacePath: String?
    /// The tool's own session ID.
    var sessionID: String?
    var task: String?
    var status: DeveloperActivityStatus
    var statusMessage: String?
    /// When the current task started.
    var startedAt: Date
    /// When the last message about the session arrived.
    var updatedAt: Date
    /// When the session finished (completed, failed or cancelled); nil while it is active.
    var finishedAt: Date?
    /// Completion fraction in `0...1`.
    var progress: Double?
    /// Bundle identifier of the terminal or editor the session runs in. Untrusted: only known apps
    /// are ever brought forward.
    var terminalBundleID: String?

    /// Creates a session from its first `event` message. Nil for messages without a status or provider.
    init?(message: DeveloperBridgeMessage, id: String, now: Date) {
        guard let status = message.status, let provider = message.provider, let sessionKey = message.sessionKey else { return nil }
        self.id = id
        self.sessionKey = sessionKey
        integrationID = provider
        self.status = status
        startedAt = now
        updatedAt = now
        finishedAt = status.isFinished ? now : nil
        merge(message)
    }

    /// "Claude Code": the reported name, a known integration's name, or the ID title-cased.
    var providerName: String {
        reportedProviderName ?? DeveloperProviderNames.name(for: integrationID)
    }

    /// "Claude": a known integration's short name, otherwise `providerName`.
    var shortName: String {
        DeveloperProviderNames.shortName(for: integrationID) ?? providerName
    }

    /// The reported project, otherwise the workspace folder's name.
    var project: String? {
        if let reportedProject { return reportedProject }
        guard let workspacePath else { return nil }
        let name = (workspacePath as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    /// Applies a later `event` message about this session.
    mutating func apply(_ message: DeveloperBridgeMessage, now: Date) {
        guard let newStatus = message.status else { return }
        if status.isFinished, !newStatus.isFinished {
            // Finished, then busy again: a new task.
            startedAt = now
            finishedAt = nil
            task = nil
            statusMessage = nil
            progress = nil
        } else if newStatus != status {
            // A status message describes the status it came with.
            statusMessage = nil
        }
        if newStatus.isFinished, newStatus != status || finishedAt == nil {
            finishedAt = now
        }
        status = newStatus
        updatedAt = now
        merge(message)
    }

    /// Copies the fields the message carries.
    private mutating func merge(_ message: DeveloperBridgeMessage) {
        if let value = message.providerName { reportedProviderName = value }
        if let value = message.project { reportedProject = value }
        if let value = message.workspace { workspacePath = value }
        if let value = message.session { sessionID = value }
        if let value = message.task { task = value }
        if let value = message.message { statusMessage = value }
        if let value = message.progress { progress = min(max(value, 0), 1) }
        if let value = message.terminal { terminalBundleID = value }
    }
}

/// Every known agent session and the rules that add, update and remove them. A value type with no
/// clocks or side effects, so the feature's lifecycle is unit tested directly.
struct DeveloperSessionCollection: Equatable, Sendable {
    /// More sessions than this is almost certainly a misbehaving tool; finished ones leave first,
    /// then the least recently updated.
    static let maximumSessions = 12

    /// In order of first sight.
    private(set) var sessions: [DeveloperActivity] = []

    var isEmpty: Bool { sessions.isEmpty }

    func session(id: DeveloperActivity.ID) -> DeveloperActivity? {
        sessions.first { $0.id == id }
    }

    func session(forKey key: String) -> DeveloperActivity? {
        sessions.first { $0.sessionKey == key }
    }

    /// Applies a validated message: an `event` creates or updates its session, an `end` removes it,
    /// a `ping` changes nothing.
    /// - Returns: The ID of the session the message was about, if any.
    @discardableResult
    mutating func apply(
        _ message: DeveloperBridgeMessage,
        now: Date,
        makeID: () -> String = { UUID().uuidString }
    ) -> DeveloperActivity.ID? {
        guard let key = message.sessionKey else { return nil }
        let index = sessions.firstIndex { $0.sessionKey == key }
        switch message.type {
        case .ping:
            return nil
        case .end:
            guard let index else { return nil }
            return sessions.remove(at: index).id
        case .event:
            if let index {
                sessions[index].apply(message, now: now)
                return sessions[index].id
            }
            guard let session = DeveloperActivity(message: message, id: makeID(), now: now) else { return nil }
            sessions.append(session)
            trimToLimit(keeping: session.id)
            return session.id
        }
    }

    /// Removes a session, e.g. because the user dismissed it.
    @discardableResult
    mutating func remove(id: DeveloperActivity.ID) -> DeveloperActivity? {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return nil }
        return sessions.remove(at: index)
    }

    mutating func removeAll() {
        sessions.removeAll()
    }

    /// Removes sessions the rules no longer show at `date`: finished long enough ago, or stale.
    @discardableResult
    mutating func removeExpired(at date: Date) -> [DeveloperActivity] {
        var expired: [DeveloperActivity] = []
        sessions.removeAll { session in
            guard DeveloperActivityRules.phase(for: session, at: date) == nil else { return false }
            expired.append(session)
            return true
        }
        return expired
    }

    /// The next moment any session changes phase or leaves. Nil when nothing will by time alone.
    func nextBoundary(after date: Date) -> Date? {
        sessions.compactMap { DeveloperActivityRules.nextBoundary(for: $0, after: date) }.min()
    }

    /// Drops sessions beyond the limit, never the one that just arrived.
    private mutating func trimToLimit(keeping newID: DeveloperActivity.ID) {
        while sessions.count > Self.maximumSessions {
            let others = sessions.indices.filter { sessions[$0].id != newID }
            let finished = others.filter { sessions[$0].status.isFinished }
            let candidates = finished.isEmpty ? others : finished
            guard let oldest = candidates.min(by: { sessions[$0].updatedAt < sessions[$1].updatedAt }) else { return }
            sessions.remove(at: oldest)
        }
    }
}
