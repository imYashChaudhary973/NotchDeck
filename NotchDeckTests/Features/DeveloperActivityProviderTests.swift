import Foundation
import Testing
@testable import NotchDeck

@MainActor
final class FakeDeveloperEventSource: DeveloperEventSource {
    /// Thrown by `start` while set.
    var startError: (any Error)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onMessage: (@MainActor (DeveloperBridgeMessage) -> Void)?

    var isListening: Bool { onMessage != nil }

    func start(onMessage: @escaping @MainActor (DeveloperBridgeMessage) -> Void) throws {
        startCount += 1
        if let startError { throw startError }
        self.onMessage = onMessage
    }

    func stop() {
        stopCount += 1
        onMessage = nil
    }

    /// Delivers a message as the bridge would.
    func send(_ message: DeveloperBridgeMessage) {
        onMessage?(message)
    }
}

struct FakeBridgeError: LocalizedError {
    var errorDescription: String? { "The socket is already in use." }
}

@MainActor
final class FakeDeveloperWorkspace: DeveloperWorkspaceOpening {
    var running: Set<String> = []
    private(set) var activated: [String] = []
    private(set) var openedInTerminal: [URL] = []
    private(set) var openedInFinder: [URL] = []

    var openedAnything: Bool { !activated.isEmpty || !openedInTerminal.isEmpty || !openedInFinder.isEmpty }

    func isRunning(bundleIdentifier: String) -> Bool { running.contains(bundleIdentifier) }
    func activate(bundleIdentifier: String) { activated.append(bundleIdentifier) }
    func openInTerminal(_ directory: URL) { openedInTerminal.append(directory) }
    func openInFinder(_ directory: URL) { openedInFinder.append(directory) }
}

@MainActor
struct DeveloperActivityProviderTests {
    let clock = TestClock()
    let engine: ActivityEngine
    let events = FakeDeveloperEventSource()
    let workspace = FakeDeveloperWorkspace()
    let source = ActivitySource(rawValue: "developer")

    init() {
        let clock = clock
        engine = ActivityEngine(now: { clock.now }, schedulesExpiry: false)
    }

    @discardableResult
    func start() -> DeveloperActivityProvider {
        let provider = DeveloperActivityProvider(source: events, workspace: workspace, now: { [clock] in clock.now }, schedulesWakeUps: false)
        engine.register(provider)
        return provider
    }

    func key(_ provider: DeveloperActivityProvider, session: String = "s1", integration: String = "claude-code") -> ActivityKey? {
        guard let id = provider.sessions.session(forKey: "\(integration)|session:\(session)")?.id else { return nil }
        return ActivityKey(source: source, id: DeveloperActivityProvider.activityID(for: id))
    }

    func activity(_ provider: DeveloperActivityProvider, session: String = "s1", integration: String = "claude-code") -> NotchActivity? {
        key(provider, session: session, integration: integration).flatMap(engine.activity(for:))
    }

    func agent(_ activity: NotchActivity?) -> AgentContent? {
        if case .agent(let agent) = activity?.presentation.content { agent } else { nil }
    }

    /// Moves time on and lets both the provider and the engine catch up.
    func advance(_ provider: DeveloperActivityProvider, by seconds: TimeInterval) {
        clock.advance(by: seconds)
        provider.advance()
        engine.expireActivities()
    }

    func perform(_ actionID: String, _ provider: DeveloperActivityProvider, session: String = "s1") throws {
        engine.perform(actionID: actionID, on: try #require(key(provider, session: session)))
    }

    func makeDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "NotchDeckTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Source

    @Test func startingListensAndShowsNothingUntilAToolReports() {
        start()
        #expect(events.startCount == 1)
        #expect(events.isListening)
        #expect(engine.resolution == .empty)
    }

    @Test func messagesFromTheSourceBecomeAgentActivities() throws {
        let provider = start()
        events.send(.agent(.working, project: "Rove", workspace: "/Users/me/Rove", task: "Implement tab management"))

        let activity = try #require(activity(provider))
        #expect(activity.kind == .agent)
        #expect(activity.placement == .notch)
        #expect(activity.priority == DeveloperActivityRules.workingPriority)
        #expect(activity.title == "Claude · Rove")
        #expect(activity.subtitle == "Implement tab management")
        #expect(activity.startedAt == clock.now)
        #expect(activity.presentation.symbolName == "asterisk")
        #expect(activity.presentation.accent == .orange)
        #expect(activity.presentation.statusText == "Working")
        #expect(activity.presentation.compactAccessory == .elapsed(since: clock.now))
        #expect(agent(activity) == AgentContent(
            providerName: "Claude Code", shortName: "Claude", project: "Rove", task: "Implement tab management",
            statusText: "Working", tone: .working, startedAt: clock.now
        ))
        #expect(engine.resolution.primary?.key == activity.key)
    }

    @Test func pingsAndMessagesWhileStoppedAreIgnored() {
        let provider = DeveloperActivityProvider(source: events, workspace: workspace, now: { [clock] in clock.now }, schedulesWakeUps: false)
        provider.receive(.agent(.working))
        #expect(provider.sessions.isEmpty)

        engine.register(provider)
        provider.receive(DeveloperBridgeMessage(type: .ping))
        #expect(provider.sessions.isEmpty)
        #expect(engine.resolution == .empty)
    }

    @Test func aSourceThatCannotStartShowsARetryRow() throws {
        events.startError = FakeBridgeError()
        let provider = start()
        let bridgeKey = ActivityKey(source: source, id: DeveloperActivityProvider.bridgeActivityID)

        let row = try #require(engine.activity(for: bridgeKey))
        #expect(row.placement == .commandCenter)
        #expect(row.title == "Developer bridge unavailable")
        #expect(row.subtitle == "The socket is already in use.")
        #expect(row.actions.map(\.id) == [DeveloperActivityProvider.ActionID.retry])
        #expect(engine.resolution.primary == nil)

        // The feature keeps working (e.g. for messages injected by the debug panel).
        provider.receive(.agent(.working))
        #expect(activity(provider) != nil)

        // Retrying still fails: the row stays.
        engine.perform(actionID: DeveloperActivityProvider.ActionID.retry, on: bridgeKey)
        #expect(events.startCount == 2)
        #expect(engine.activity(for: bridgeKey) != nil)

        events.startError = nil
        engine.perform(actionID: DeveloperActivityProvider.ActionID.retry, on: bridgeKey)
        #expect(events.startCount == 3)
        #expect(events.isListening)
        #expect(engine.activity(for: bridgeKey) == nil)
    }

    @Test func turningTheFeatureOffStopsTheSourceAndForgetsSessions() {
        let provider = start()
        events.send(.agent(.working))

        engine.unregister(source)

        #expect(events.stopCount == 1)
        #expect(!events.isListening)
        #expect(provider.sessions.isEmpty)
        #expect(engine.resolution == .empty)
        provider.receive(.agent(.working))
        #expect(provider.sessions.isEmpty)
    }

    // MARK: Lifecycle

    @Test func lifecycleFromWorkingThroughPermissionToFinished() throws {
        let provider = start()
        let started = clock.now
        events.send(.agent(.working, project: "Rove", task: "Implement tab management"))

        clock.advance(by: 60)
        events.send(.agent(.needsPermission, message: "Claude needs your permission to use Bash"))
        var current = try #require(activity(provider))
        #expect(current.priority == .attentionRequired)
        #expect(current.title == "Claude needs you")
        #expect(current.subtitle == "Rove · Claude needs your permission to use Bash")
        #expect(current.presentation.statusText == "Needs permission")
        #expect(current.presentation.compactAccessory == .symbol("hand.raised.fill"))
        #expect(agent(current)?.tone == .attention)

        clock.advance(by: 30)
        events.send(.agent(.working))
        current = try #require(activity(provider))
        #expect(current.priority == DeveloperActivityRules.workingPriority)
        #expect(current.subtitle == "Implement tab management")
        // Still the same task: elapsed time counts from the first message.
        #expect(current.presentation.compactAccessory == .elapsed(since: started))

        clock.advance(by: 600)
        events.send(.agent(.completed))
        current = try #require(activity(provider))
        #expect(current.placement == .notch)
        #expect(current.priority == .active)
        #expect(current.title == "Rove finished")
        #expect(current.subtitle == "Claude · Implement tab management")
        #expect(current.presentation.statusText == "Finished")
        #expect(current.presentation.compactAccessory == .symbol("checkmark"))
        #expect(agent(current)?.endedAt == clock.now)
        #expect(agent(current)?.tone == .success)

        advance(provider, by: DeveloperActivityRules.completedNotchDuration)
        current = try #require(activity(provider))
        #expect(current.placement == .commandCenter)
        #expect(current.priority == DeveloperActivityRules.completedListPriority)
        #expect(engine.resolution.primary == nil)

        advance(provider, by: DeveloperActivityRules.finishedListDuration - DeveloperActivityRules.completedNotchDuration)
        #expect(provider.sessions.isEmpty)
        #expect(engine.resolution == .empty)
    }

    @Test func endRemovesTheSessionAtOnce() {
        let provider = start()
        events.send(.agent(.working))
        events.send(.agent(.working, session: "other"))

        events.send(.ending())

        #expect(activity(provider) == nil)
        #expect(activity(provider, session: "other") != nil)
    }

    @Test func dismissRemovesFinishedAndStuckSessions() throws {
        let provider = start()
        events.send(.agent(.completed))
        events.send(.agent(.working, session: "stuck"))
        #expect(activity(provider)?.actions.last?.id == DeveloperActivityProvider.ActionID.dismiss)
        #expect(activity(provider, session: "stuck")?.actions.last?.id == DeveloperActivityProvider.ActionID.dismiss)

        try perform(DeveloperActivityProvider.ActionID.dismiss, provider)
        try perform(DeveloperActivityProvider.ActionID.dismiss, provider, session: "stuck")

        #expect(provider.sessions.isEmpty)
        #expect(engine.resolution == .empty)
    }

    @Test func aFailedSessionPeeksThenWaitsInTheCommandCenter() throws {
        let provider = start()
        events.send(.agent(.working, provider: "my-tool", project: "NotchApp", task: "Release build"))
        events.send(.agent(.failed, provider: "my-tool", message: "Build failed: 3 errors"))

        var failed = try #require(activity(provider, integration: "my-tool"))
        #expect(failed.placement == .notch)
        #expect(failed.priority == .attentionRequired)
        #expect(failed.title == "My Tool failed")
        #expect(failed.subtitle == "NotchApp · Build failed: 3 errors")
        #expect(failed.presentation.accent == .red)
        #expect(failed.presentation.symbolName == "terminal")
        #expect(failed.presentation.compactAccessory == .symbol("exclamationmark.triangle.fill"))
        #expect(agent(failed)?.tone == .failure)

        advance(provider, by: DeveloperActivityRules.failedNotchDuration)
        failed = try #require(activity(provider, integration: "my-tool"))
        #expect(failed.placement == .commandCenter)
        #expect(failed.priority == DeveloperActivityRules.failedListPriority)

        advance(provider, by: DeveloperActivityRules.finishedListDuration)
        #expect(activity(provider, integration: "my-tool") == nil)
    }

    @Test func aCancelledSessionShowsBrieflyThenLeaves() throws {
        let provider = start()
        events.send(.agent(.working, project: "Rove"))
        events.send(.agent(.cancelled))

        let cancelled = try #require(activity(provider))
        #expect(cancelled.title == "Rove cancelled")
        #expect(cancelled.priority == .passive)
        #expect(cancelled.presentation.compactAccessory == .symbol("xmark"))
        #expect(cancelled.expiresAt == clock.now.addingTimeInterval(DeveloperActivityRules.cancelledNotchDuration))

        advance(provider, by: DeveloperActivityRules.cancelledNotchDuration)
        #expect(provider.sessions.isEmpty)
        #expect(engine.resolution == .empty)
    }

    @Test func silentBusySessionsAreRemovedAfterThirtyMinutes() {
        let provider = start()
        events.send(.agent(.working))
        events.send(.agent(.waiting, session: "waiting"))

        advance(provider, by: DeveloperActivityRules.activeStaleInterval - 60)
        // A new message keeps a session alive.
        events.send(.agent(.runningCommand))
        advance(provider, by: 60)

        #expect(activity(provider) != nil)
        #expect(activity(provider, session: "waiting") == nil)

        advance(provider, by: DeveloperActivityRules.activeStaleInterval)
        #expect(activity(provider) == nil)
    }

    @Test func sessionsNeedingAttentionAreRemovedAfterEightHours() {
        let provider = start()
        events.send(.agent(.needsInput))

        advance(provider, by: DeveloperActivityRules.activeStaleInterval)
        #expect(activity(provider) != nil)

        advance(provider, by: DeveloperActivityRules.attentionStaleInterval - DeveloperActivityRules.activeStaleInterval)
        #expect(activity(provider) == nil)
    }

    @Test func theEngineRemovesAStaleSessionEvenIfTheProviderNeverWakes() throws {
        let provider = start()
        events.send(.agent(.working))
        let key = try #require(key(provider))

        clock.advance(by: DeveloperActivityRules.activeStaleInterval)
        engine.expireActivities()

        #expect(engine.activity(for: key) == nil)
    }

    @Test func theNextPromptAfterFinishingStartsANewTask() throws {
        let provider = start()
        events.send(.agent(.working, project: "Rove", task: "Implement tabs"))
        clock.advance(by: 300)
        events.send(.agent(.completed))
        let firstID = try #require(key(provider))

        clock.advance(by: 60)
        events.send(.agent(.working))

        let next = try #require(activity(provider))
        #expect(next.key == firstID)
        #expect(next.startedAt == clock.now)
        #expect(next.presentation.compactAccessory == .elapsed(since: clock.now))
        #expect(next.subtitle == nil)
        #expect(agent(next)?.endedAt == nil)
    }

    @Test func progressIsShownAsARing() throws {
        let provider = start()
        events.send(.agent(.runningCommand, progress: 0.4))

        let current = try #require(activity(provider))
        #expect(current.progress == 0.4)
        #expect(current.presentation.compactAccessory == .progress)
        #expect(current.presentation.statusText == "Running command")
    }

    // MARK: Multiple agents

    @Test func theAgentThatNeedsYouTakesTheNotchAndTheOthersWait() throws {
        let provider = start()
        events.send(.agent(.working, session: "rove", project: "Rove"))
        events.send(.agent(.working, provider: "codex", session: "zen", project: "ZenVoice"))
        events.send(.agent(.needsInput, session: "notch", workspace: "/Users/me/NotchApp"))

        let needsYou = try #require(key(provider, session: "notch"))
        #expect(engine.resolution.primary?.key == needsYou)
        #expect(engine.resolution.queued.count == 2)
        #expect(Set(engine.resolution.queued.map(\.title)) == ["Claude · Rove", "Codex · ZenVoice"])
        #expect(engine.resolution.all.allSatisfy { $0.kind == .agent })

        // Once it is answered and the session ends, a working agent returns to the notch.
        events.send(.ending(session: "notch"))
        #expect(engine.resolution.primary?.priority == DeveloperActivityRules.workingPriority)
        #expect(engine.resolution.all.count == 2)
    }

    @Test func agentsAtEqualPriorityDoNotFlap() throws {
        let provider = start()
        events.send(.agent(.working, session: "a"))
        let first = try #require(key(provider, session: "a"))

        events.send(.agent(.working, provider: "codex", session: "b"))
        #expect(engine.resolution.primary?.key == first)

        events.send(.agent(.runningCommand, provider: "codex", session: "b", message: "swift test"))
        events.send(.agent(.runningCommand, session: "a"))
        events.send(.agent(.working, provider: "codex", session: "b"))
        #expect(engine.resolution.primary?.key == first)
    }

    @Test func theSameToolInTwoWorkspacesShowsTwoSessions() {
        let provider = start()
        events.send(.agent(.working, session: nil, workspace: "/Users/me/Rove"))
        events.send(.agent(.working, session: nil, workspace: "/Users/me/NotchApp"))

        #expect(provider.sessions.sessions.map(\.project) == ["Rove", "NotchApp"])
        #expect(Set(engine.resolution.all.map(\.title)) == ["Claude · Rove", "Claude · NotchApp"])
    }

    // MARK: Actions

    @Test func actionsDependOnWhatTheSessionReported() {
        let provider = start()
        events.send(.agent(.working, session: "bare"))
        events.send(.agent(.working, session: "folder", workspace: "/Users/me/Rove"))
        events.send(.agent(.working, session: "terminal", terminal: "com.googlecode.iterm2"))
        events.send(.agent(.working, session: "unknown", terminal: "com.example.unknown"))

        typealias ID = DeveloperActivityProvider.ActionID
        #expect(activity(provider, session: "bare")?.actions.map(\.id) == [ID.dismiss])
        #expect(activity(provider, session: "folder")?.actions.map(\.id) == [ID.openTerminal, ID.openWorkspace, ID.dismiss])
        #expect(activity(provider, session: "terminal")?.actions.map(\.id) == [ID.openTerminal, ID.dismiss])
        #expect(activity(provider, session: "unknown")?.actions.map(\.id) == [ID.dismiss])
    }

    @Test func openTerminalBringsAKnownRunningTerminalForward() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        workspace.running = ["com.googlecode.iterm2"]
        let provider = start()
        events.send(.agent(.needsPermission, workspace: directory.path(percentEncoded: false), terminal: "com.googlecode.iterm2"))

        try perform(DeveloperActivityProvider.ActionID.openTerminal, provider)

        #expect(workspace.activated == ["com.googlecode.iterm2"])
        #expect(workspace.openedInTerminal.isEmpty)
        // Opening the terminal doesn't answer the agent; the session stays until it reports.
        #expect(activity(provider)?.priority == .attentionRequired)
    }

    @Test(arguments: [
        "com.googlecode.iterm2",  // known, but not running
        "com.example.unknown",  // running, but not a known terminal
    ])
    func openTerminalOtherwiseOpensTheWorkspaceInTerminal(_ terminal: String) throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        workspace.running = ["com.example.unknown"]
        let provider = start()
        events.send(.agent(.working, workspace: directory.path(percentEncoded: false), terminal: terminal))

        try perform(DeveloperActivityProvider.ActionID.openTerminal, provider)

        #expect(workspace.activated.isEmpty)
        #expect(workspace.openedInTerminal.map(\.path) == [directory.resolvingSymlinksInPath().path])
    }

    @Test func openWorkspaceShowsTheFolderInFinder() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = start()
        events.send(.agent(.completed, workspace: directory.path(percentEncoded: false)))

        try perform(DeveloperActivityProvider.ActionID.openWorkspace, provider)

        #expect(workspace.openedInFinder.map(\.path) == [directory.resolvingSymlinksInPath().path])
    }

    @Test func nothingIsOpenedForAWorkspaceThatIsNotADirectory() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "script.sh")
        try Data("echo hi".utf8).write(to: file)
        let provider = start()
        events.send(.agent(.working, session: "missing", workspace: directory.appending(path: "gone").path(percentEncoded: false)))
        events.send(.agent(.working, session: "file", workspace: file.path(percentEncoded: false), terminal: "com.example.unknown"))

        for session in ["missing", "file"] {
            try perform(DeveloperActivityProvider.ActionID.openTerminal, provider, session: session)
            try perform(DeveloperActivityProvider.ActionID.openWorkspace, provider, session: session)
        }

        #expect(!workspace.openedAnything)
    }

    @Test func unknownActionsAndActivitiesAreIgnored() throws {
        let provider = start()
        events.send(.agent(.working, workspace: "/"))

        try perform("rm -rf", provider)
        engine.perform(actionID: DeveloperActivityProvider.ActionID.openWorkspace, on: ActivityKey(source: source, id: "session-unknown"))
        engine.perform(actionID: DeveloperActivityProvider.ActionID.dismiss, on: ActivityKey(source: source, id: "other"))

        #expect(!workspace.openedAnything)
        #expect(provider.sessions.sessions.count == 1)
    }
}
