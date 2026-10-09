import Foundation
import Testing
@testable import NotchDeck

extension DeveloperBridgeMessage {
    /// An `event` message with test defaults: Claude Code, session `s1`.
    static func agent(
        _ status: DeveloperActivityStatus,
        provider: String = "claude-code",
        providerName: String? = nil,
        session: String? = "s1",
        project: String? = nil,
        workspace: String? = nil,
        task: String? = nil,
        message: String? = nil,
        progress: Double? = nil,
        terminal: String? = nil
    ) -> DeveloperBridgeMessage {
        DeveloperBridgeMessage(
            provider: provider, providerName: providerName, session: session, project: project, workspace: workspace,
            task: task, status: status, message: message, progress: progress, terminal: terminal
        )
    }

    /// An `end` message for a session.
    static func ending(provider: String = "claude-code", session: String? = "s1", workspace: String? = nil) -> DeveloperBridgeMessage {
        DeveloperBridgeMessage(type: .end, provider: provider, session: session, workspace: workspace)
    }
}

struct DeveloperActivityModelTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func session(_ message: DeveloperBridgeMessage) throws -> DeveloperActivity {
        try #require(DeveloperActivity(message: message, id: "id", now: start))
    }

    @Test func knownProvidersHaveProperNamesAndOthersAreTitleCased() throws {
        let claude = try session(.agent(.working))
        #expect(claude.providerName == "Claude Code")
        #expect(claude.shortName == "Claude")

        let codex = try session(.agent(.working, provider: "codex"))
        #expect(codex.providerName == "Codex")
        #expect(codex.shortName == "Codex")

        let other = try session(.agent(.working, provider: "my-tool"))
        #expect(other.providerName == "My Tool")
        #expect(other.shortName == "My Tool")
        #expect(DeveloperProviderNames.titleCased("acme_bot.v2") == "Acme Bot V2")
    }

    @Test func aReportedProviderNameWins() throws {
        let other = try session(.agent(.working, provider: "my-tool", providerName: "Builder"))
        #expect(other.providerName == "Builder")
        #expect(other.shortName == "Builder")

        // A known tool keeps its short name for compact text.
        let claude = try session(.agent(.working, providerName: "Claude Code Beta"))
        #expect(claude.providerName == "Claude Code Beta")
        #expect(claude.shortName == "Claude")
    }

    @Test func projectDefaultsToTheWorkspaceFolderName() throws {
        #expect(try session(.agent(.working, workspace: "/Users/me/Developer/Rove")).project == "Rove")
        #expect(try session(.agent(.working, project: "Rove App", workspace: "/Users/me/rove")).project == "Rove App")
        #expect(try session(.agent(.working, workspace: "/")).project == nil)
        #expect(try session(.agent(.working)).project == nil)
    }

    @Test func messagesWithoutAStatusDoNotCreateASession() {
        #expect(DeveloperActivity(message: .ending(), id: "id", now: start) == nil)
    }

    @Test func absentFieldsKeepTheirValues() throws {
        var activity = try session(.agent(.working, project: "Rove", workspace: "/tmp/rove", task: "Implement tabs",
                                          message: "Reading files", progress: 0.2, terminal: "com.apple.Terminal"))
        activity.apply(.agent(.working), now: start.addingTimeInterval(5))

        #expect(activity.project == "Rove")
        #expect(activity.workspacePath == "/tmp/rove")
        #expect(activity.task == "Implement tabs")
        #expect(activity.statusMessage == "Reading files")
        #expect(activity.progress == 0.2)
        #expect(activity.terminalBundleID == "com.apple.Terminal")
        #expect(activity.updatedAt == start.addingTimeInterval(5))
    }

    @Test func presentFieldsReplaceStoredValues() throws {
        var activity = try session(.agent(.working, project: "Rove", task: "Implement tabs", progress: 0.2))
        activity.apply(.agent(.runningCommand, project: "Rove 2", task: "Run tests", message: "swift test", progress: 0.5),
                       now: start.addingTimeInterval(5))

        #expect(activity.status == .runningCommand)
        #expect(activity.project == "Rove 2")
        #expect(activity.task == "Run tests")
        #expect(activity.statusMessage == "swift test")
        #expect(activity.progress == 0.5)
    }

    @Test func aStatusMessageIsClearedWhenTheStatusChangesWithoutOne() throws {
        var activity = try session(.agent(.needsPermission, task: "Implement tabs", message: "Claude needs your permission to use Bash"))
        activity.apply(.agent(.working), now: start.addingTimeInterval(5))

        #expect(activity.statusMessage == nil)
        #expect(activity.task == "Implement tabs")
        // Same task: the elapsed time keeps counting.
        #expect(activity.startedAt == start)
    }

    @Test func aFinishedSessionThatBecomesActiveStartsANewTask() throws {
        var activity = try session(.agent(.working, task: "Implement tabs", progress: 0.4))
        let finished = start.addingTimeInterval(60)
        activity.apply(.agent(.completed, message: "Done"), now: finished)
        #expect(activity.finishedAt == finished)
        #expect(activity.startedAt == start)

        let next = start.addingTimeInterval(120)
        activity.apply(.agent(.working), now: next)

        #expect(activity.startedAt == next)
        #expect(activity.finishedAt == nil)
        #expect(activity.task == nil)
        #expect(activity.statusMessage == nil)
        #expect(activity.progress == nil)
    }

    @Test func finishingAgainWithTheSameStatusKeepsTheFinishTime() throws {
        var activity = try session(.agent(.completed))
        #expect(activity.finishedAt == start)

        activity.apply(.agent(.completed), now: start.addingTimeInterval(5))
        #expect(activity.finishedAt == start)

        activity.apply(.agent(.failed), now: start.addingTimeInterval(8))
        #expect(activity.finishedAt == start.addingTimeInterval(8))
    }
}

struct DeveloperSessionCollectionTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func eventsCreateAndUpdateSessionsWithStableIDs() throws {
        var collection = DeveloperSessionCollection()
        let created = collection.apply(.agent(.working, workspace: "/Users/me/Rove"), now: start)
        let id = try #require(created)
        let again = collection.apply(.agent(.needsInput), now: start.addingTimeInterval(1))

        #expect(again == id)
        #expect(collection.sessions.count == 1)
        #expect(collection.session(id: id)?.status == .needsInput)
        // IDs never carry paths or other reported text.
        #expect(!id.contains("/"))
        #expect(!id.contains("Rove"))
    }

    @Test func sessionsAreKeyedByProviderAndSession() {
        var collection = DeveloperSessionCollection()
        collection.apply(.agent(.working, session: "a"), now: start)
        collection.apply(.agent(.working, session: "b"), now: start)
        collection.apply(.agent(.working, provider: "codex", session: "a"), now: start)
        // Without a session ID, the workspace tells sessions apart.
        collection.apply(.agent(.working, session: nil, workspace: "/Users/me/Rove"), now: start)
        collection.apply(.agent(.working, session: nil, workspace: "/Users/me/NotchApp"), now: start)

        #expect(collection.sessions.count == 5)
        #expect(Set(collection.sessions.map(\.id)).count == 5)
        #expect(collection.session(forKey: "claude-code|workspace:/Users/me/NotchApp")?.project == "NotchApp")
    }

    @Test func endRemovesTheSessionAndPingsChangeNothing() {
        var collection = DeveloperSessionCollection()
        let id = collection.apply(.agent(.working), now: start)
        collection.apply(DeveloperBridgeMessage(type: .ping), now: start)
        #expect(collection.sessions.count == 1)

        #expect(collection.apply(.ending(session: "unknown"), now: start) == nil)
        #expect(collection.apply(.ending(), now: start) == id)
        #expect(collection.isEmpty)
    }

    @Test func removingByIDDismissesASession() throws {
        var collection = DeveloperSessionCollection()
        let created = collection.apply(.agent(.completed), now: start)
        let id = try #require(created)

        #expect(collection.remove(id: id)?.status == .completed)
        #expect(collection.isEmpty)
        #expect(collection.remove(id: id) == nil)
    }

    @Test func overTheLimitTheOldestFinishedSessionLeavesFirst() {
        var collection = DeveloperSessionCollection()
        collection.apply(.agent(.working, session: "old-working"), now: start)
        collection.apply(.agent(.completed, session: "old-finished"), now: start.addingTimeInterval(1))
        collection.apply(.agent(.completed, session: "newer-finished"), now: start.addingTimeInterval(2))
        for index in 3..<DeveloperSessionCollection.maximumSessions {
            collection.apply(.agent(.working, session: "s\(index)"), now: start.addingTimeInterval(Double(index)))
        }
        #expect(collection.sessions.count == DeveloperSessionCollection.maximumSessions)

        collection.apply(.agent(.working, session: "new"), now: start.addingTimeInterval(100))

        #expect(collection.sessions.count == DeveloperSessionCollection.maximumSessions)
        #expect(collection.session(forKey: "claude-code|session:old-finished") == nil)
        #expect(collection.session(forKey: "claude-code|session:newer-finished") != nil)
        #expect(collection.session(forKey: "claude-code|session:old-working") != nil)
        #expect(collection.session(forKey: "claude-code|session:new") != nil)
    }

    @Test func withoutFinishedSessionsTheLeastRecentlyUpdatedLeaves() {
        var collection = DeveloperSessionCollection()
        for index in 0..<DeveloperSessionCollection.maximumSessions {
            collection.apply(.agent(.working, session: "s\(index)"), now: start.addingTimeInterval(Double(index)))
        }
        // s0 is the oldest, but it just reported in; s1 is now the least recently updated.
        collection.apply(.agent(.runningCommand, session: "s0"), now: start.addingTimeInterval(50))

        // Even a finished newcomer is kept: it is what just happened.
        collection.apply(.agent(.completed, session: "new"), now: start.addingTimeInterval(60))

        #expect(collection.session(forKey: "claude-code|session:s1") == nil)
        #expect(collection.session(forKey: "claude-code|session:s0") != nil)
        #expect(collection.session(forKey: "claude-code|session:new") != nil)
    }

    @Test func expiredSessionsAreRemovedAndTheNextBoundaryIsReported() {
        var collection = DeveloperSessionCollection()
        collection.apply(.agent(.working, session: "busy"), now: start)
        collection.apply(.agent(.cancelled, session: "cancelled"), now: start)
        #expect(collection.nextBoundary(after: start) == start.addingTimeInterval(DeveloperActivityRules.cancelledNotchDuration))

        let removed = collection.removeExpired(at: start.addingTimeInterval(DeveloperActivityRules.cancelledNotchDuration))

        #expect(removed.map(\.status) == [.cancelled])
        #expect(collection.sessions.map(\.status) == [.working])
        #expect(collection.nextBoundary(after: start) == start.addingTimeInterval(DeveloperActivityRules.activeStaleInterval))
    }
}

struct DeveloperActivityRulesTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func session(_ status: DeveloperActivityStatus) throws -> DeveloperActivity {
        try #require(DeveloperActivity(message: .agent(status), id: "id", now: start))
    }

    func phase(_ session: DeveloperActivity, after seconds: TimeInterval) -> DeveloperSessionPhase? {
        DeveloperActivityRules.phase(for: session, at: start.addingTimeInterval(seconds))
    }

    @Test(arguments: [
        (DeveloperActivityStatus.starting, 25),
        (.working, 25),
        (.runningCommand, 25),
        (.waiting, 30),
        (.needsInput, 50),
        (.needsPermission, 50),
        (.completed, 30),
        (.failed, 50),
        (.cancelled, 20),
    ])
    func everyStatusStartsOnTheNotch(_ status: DeveloperActivityStatus, priority: Int) throws {
        let phase = try #require(phase(try session(status), after: 0))
        #expect(phase.placement == .notch)
        #expect(phase.priority.rawValue == priority)
    }

    @Test func aWorkingAgentRanksBetweenMusicAndAMeetingOrTimer() {
        // Music plays at Passive (20).
        #expect(DeveloperActivityRules.workingPriority > .passive)
        #expect(DeveloperActivityRules.workingPriority < CalendarRules.standard.rules[0].priority)
        #expect(DeveloperActivityRules.workingPriority < TimerPhase.running.priority)
        #expect(DeveloperActivityRules.attentionPriority > ActivityPriority.timeSensitive)
    }

    @Test func busyAndWaitingSessionsGoStaleAfterThirtySilentMinutes() throws {
        for status in [DeveloperActivityStatus.starting, .working, .runningCommand, .waiting] {
            let session = try session(status)
            let stale = DeveloperActivityRules.activeStaleInterval
            #expect(phase(session, after: stale - 1) != nil)
            #expect(phase(session, after: stale) == nil)
            #expect(phase(session, after: 0)?.removesAtEnd == true)
            #expect(DeveloperActivityRules.boundaries(for: session) == [start.addingTimeInterval(stale)])
        }
    }

    @Test func sessionsNeedingAttentionGoStaleAfterEightHours() throws {
        for status in [DeveloperActivityStatus.needsInput, .needsPermission] {
            let session = try session(status)
            #expect(phase(session, after: DeveloperActivityRules.activeStaleInterval) != nil)
            #expect(phase(session, after: DeveloperActivityRules.attentionStaleInterval - 1) != nil)
            #expect(phase(session, after: DeveloperActivityRules.attentionStaleInterval) == nil)
        }
    }

    @Test func aCompletedSessionMovesToTheCommandCenterThenLeaves() throws {
        let session = try session(.completed)

        #expect(phase(session, after: 9.9) == DeveloperSessionPhase(
            placement: .notch, priority: .active, endsAt: start.addingTimeInterval(10), removesAtEnd: false))
        #expect(phase(session, after: 10) == DeveloperSessionPhase(
            placement: .commandCenter, priority: ActivityPriority(rawValue: 15), endsAt: start.addingTimeInterval(3600), removesAtEnd: true))
        #expect(phase(session, after: 3600) == nil)
        #expect(DeveloperActivityRules.nextBoundary(for: session, after: start) == start.addingTimeInterval(10))
        #expect(DeveloperActivityRules.nextBoundary(for: session, after: start.addingTimeInterval(10)) == start.addingTimeInterval(3600))
        #expect(DeveloperActivityRules.nextBoundary(for: session, after: start.addingTimeInterval(3600)) == nil)
    }

    @Test func aFailedSessionStaysOnTheNotchForThirtySeconds() throws {
        let session = try session(.failed)

        #expect(phase(session, after: 29)?.placement == .notch)
        #expect(phase(session, after: 29)?.priority == .attentionRequired)
        #expect(phase(session, after: 30)?.placement == .commandCenter)
        #expect(phase(session, after: 30)?.priority == ActivityPriority(rawValue: 18))
        #expect(phase(session, after: 3600) == nil)
    }

    @Test func aCancelledSessionLeavesAfterFiveSeconds() throws {
        let session = try session(.cancelled)

        #expect(phase(session, after: 4.9)?.priority == .passive)
        #expect(phase(session, after: 5) == nil)
    }

    @Test func finishedPhasesCountFromTheFinishNotTheStart() throws {
        var session = try session(.working)
        let finished = start.addingTimeInterval(600)
        session.apply(.agent(.completed), now: finished)

        #expect(DeveloperActivityRules.phase(for: session, at: finished.addingTimeInterval(9))?.placement == .notch)
        #expect(DeveloperActivityRules.phase(for: session, at: finished.addingTimeInterval(10))?.placement == .commandCenter)
    }
}

struct DeveloperWorkspaceValidatorTests {
    func makeDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "NotchDeckTests-\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func existingDirectoriesAreAcceptedWithSymlinksResolved() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = URL.temporaryDirectory.appending(path: "NotchDeckTests-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        defer { try? FileManager.default.removeItem(at: link) }

        let resolved = try #require(DeveloperWorkspaceValidator.directory(atPath: directory.path(percentEncoded: false)))
        #expect(resolved.path == directory.resolvingSymlinksInPath().path)
        #expect(DeveloperWorkspaceValidator.directory(atPath: link.path(percentEncoded: false))?.path == resolved.path)
    }

    @Test func otherPathsAreRejected() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "notes.txt")
        try Data("hi".utf8).write(to: file)
        let package = directory.appending(path: "Tool.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

        #expect(DeveloperWorkspaceValidator.directory(atPath: nil) == nil)
        #expect(DeveloperWorkspaceValidator.directory(atPath: "relative/path") == nil)
        #expect(DeveloperWorkspaceValidator.directory(atPath: directory.appending(path: "missing").path(percentEncoded: false)) == nil)
        #expect(DeveloperWorkspaceValidator.directory(atPath: file.path(percentEncoded: false)) == nil)
        #expect(DeveloperWorkspaceValidator.directory(atPath: package.path(percentEncoded: false)) == nil)
    }
}
