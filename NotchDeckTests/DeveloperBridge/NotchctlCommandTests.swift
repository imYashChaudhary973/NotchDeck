import Foundation
import Testing
@testable import NotchDeck

struct NotchctlCommandTests {
    private let currentDirectory = "/Users/me/Projects/Rove"
    private let environment = ["TERM_PROGRAM": "Apple_Terminal"]

    private func parse(_ arguments: [String], environment: [String: String]? = nil) throws(NotchctlUsageError) -> NotchctlCommand {
        try NotchctlCommand.parse(arguments: arguments, environment: environment ?? self.environment, currentDirectory: currentDirectory)
    }

    private func agentMessage(_ arguments: [String], environment: [String: String]? = nil) throws -> DeveloperBridgeMessage {
        let action = try parse(["agent"] + arguments, environment: environment).action
        guard case .agent(let message) = action else {
            Issue.record("Expected an agent message, got \(action)")
            return DeveloperBridgeMessage()
        }
        return message
    }

    // MARK: agent

    @Test(arguments: [
        ("start", DeveloperActivityStatus.starting),
        ("update", .working),
        ("working", .working),
        ("command", .runningCommand),
        ("waiting", .waiting),
        ("input", .needsInput),
        ("permission", .needsPermission),
        ("complete", .completed),
        ("fail", .failed),
        ("cancel", .cancelled),
    ])
    func everyAgentEventReportsItsStatus(event: String, status: DeveloperActivityStatus) throws {
        let message = try agentMessage([event, "--provider", "my-tool"])
        #expect(message.type == .event)
        #expect(message.status == status)
        #expect(try message.validated().status == status)
    }

    @Test func endSendsAnEndMessage() throws {
        let message = try agentMessage(["end", "--provider", "my-tool", "--session", "s1"])
        #expect(message.type == .end)
        #expect(message.status == nil)
        #expect(message.session == "s1")
    }

    @Test func coversEveryAgentEvent() {
        #expect(NotchctlAgentEvent.allCases.count == 11)
        #expect(NotchctlAgentEvent.allCases.filter { $0.status == nil } == [.end])
    }

    @Test func fillsInDefaultsFromTheEnvironment() throws {
        let message = try agentMessage(["start", "--provider", "my-tool"])
        #expect(message == DeveloperBridgeMessage(
            provider: "my-tool",
            workspace: currentDirectory,
            status: .starting,
            terminal: "com.apple.Terminal"
        ))
        let fromApp = try agentMessage(["start", "--provider", "my-tool"], environment: ["__CFBundleIdentifier": "com.mitchellh.ghostty", "TERM_PROGRAM": "Apple_Terminal"])
        #expect(fromApp.terminal == "com.mitchellh.ghostty")
        #expect(try agentMessage(["start", "--provider", "my-tool"], environment: [:]).terminal == nil)
    }

    @Test func usesEveryOption() throws {
        let message = try agentMessage([
            "update", "--provider", "Claude-Code", "--name", "Claude Code", "--session", "abc-1",
            "--project", "Tabs", "--workspace", "/Users/me/Other", "--task", "Implement tabs",
            "--message", "Running tests", "--progress", "0.25", "--terminal", "dev.zed.Zed", "--status", "runningCommand",
        ])
        #expect(message == DeveloperBridgeMessage(
            provider: "Claude-Code", providerName: "Claude Code", session: "abc-1", project: "Tabs",
            workspace: "/Users/me/Other", task: "Implement tabs", status: .runningCommand,
            message: "Running tests", progress: 0.25, terminal: "dev.zed.Zed"
        ))
        // The provider is normalized by validation, not by the parser.
        #expect(try message.validated().provider == "claude-code")
    }

    @Test func resolvesRelativeWorkspacesAgainstTheCurrentDirectory() throws {
        let message = try agentMessage(["start", "--provider", "x", "--workspace", "../Other/./App"])
        #expect(message.workspace == "/Users/me/Projects/Other/App")
        // The project is left to NotchDeck (the workspace folder's name), so a later event can't
        // replace a project reported earlier.
        #expect(message.project == nil)
    }

    @Test func acceptsTheAppAliasAndEqualsSyntax() throws {
        #expect(try agentMessage(["start", "--app", "claude"]).provider == "claude")
        #expect(try agentMessage(["start", "--provider=claude", "--message=--verbose run"]).message == "--verbose run")
        #expect(try agentMessage(["start", "--provider", "a", "--app", "b"]).provider == "b")
    }

    @Test func anEmptyTerminalTurnsDetectionOff() throws {
        #expect(try agentMessage(["start", "--provider", "x", "--terminal", ""]).terminal == nil)
    }

    @Test func updateAcceptsStatusSpellings() throws {
        #expect(try agentMessage(["update", "--provider", "x", "--status", "needsPermission"]).status == .needsPermission)
        #expect(try agentMessage(["update", "--provider", "x", "--status", "running-command"]).status == .runningCommand)
        #expect(try agentMessage(["update", "--provider", "x", "--status", "NEEDS_INPUT"]).status == .needsInput)
        #expect(throws: NotchctlUsageError.invalidValue(option: "--status", value: "thinking")) {
            try parse(["agent", "update", "--provider", "x", "--status", "thinking"])
        }
    }

    @Test func statusIsOnlyForUpdate() {
        #expect(throws: NotchctlUsageError.statusNotAllowed(.start)) {
            try parse(["agent", "start", "--provider", "x", "--status", "working"])
        }
    }

    @Test func requiresAProvider() {
        #expect(throws: NotchctlUsageError.missingOption("--provider")) { try parse(["agent", "start", "--task", "Tabs"]) }
    }

    @Test func rejectsUnknownOptionsAndArguments() {
        #expect(throws: NotchctlUsageError.unknownOption("--colour")) { try parse(["agent", "start", "--provider", "x", "--colour", "red"]) }
        #expect(throws: NotchctlUsageError.unknownOption("--colour")) { try parse(["agent", "start", "--colour=red"]) }
        #expect(throws: NotchctlUsageError.unexpectedArgument("stray")) { try parse(["agent", "start", "--provider", "x", "stray"]) }
        #expect(throws: NotchctlUsageError.unexpectedArgument("-x")) { try parse(["agent", "start", "-x"]) }
    }

    @Test func requiresOptionValues() {
        #expect(throws: NotchctlUsageError.missingValue(option: "--task")) { try parse(["agent", "start", "--provider", "x", "--task"]) }
        #expect(throws: NotchctlUsageError.missingValue(option: "--task")) { try parse(["agent", "start", "--task", "--provider", "x"]) }
    }

    @Test(arguments: ["abc", "1.5", "-0.1", "nan", "inf", ""])
    func rejectsBadProgress(progress: String) {
        #expect(throws: NotchctlUsageError.invalidValue(option: "--progress", value: progress)) {
            try parse(["agent", "working", "--provider", "x", "--progress", progress])
        }
    }

    @Test func requiresAKnownAgentEvent() {
        #expect(throws: NotchctlUsageError.missingAgentEvent) { try parse(["agent"]) }
        #expect(throws: NotchctlUsageError.missingAgentEvent) { try parse(["agent", "--provider", "x"]) }
        #expect(throws: NotchctlUsageError.unknownAgentEvent("launch")) { try parse(["agent", "launch", "--provider", "x"]) }
    }

    @Test func leavesValueChecksToValidation() throws {
        // Parsed fine, rejected by validation (exit 65 rather than 64).
        let message = try agentMessage(["start", "--provider", "Bad Name"])
        #expect(throws: DeveloperProtocolError.invalidField("provider")) { try message.validated() }
    }

    // MARK: Other commands

    @Test func parsesSend() throws {
        #expect(try parse(["send", #"{"provider":"x","status":"working"}"#]).action == .send(.json(#"{"provider":"x","status":"working"}"#)))
        #expect(try parse(["send"]).action == .send(.standardInput))
        #expect(try parse(["send", "-"]).action == .send(.standardInput))
        #expect(throws: NotchctlUsageError.unexpectedArgument("{}")) { try parse(["send", "{}", "{}"]) }
        #expect(throws: NotchctlUsageError.unknownOption("--json")) { try parse(["send", "--json"]) }
    }

    @Test func passesHookArgumentsThroughVerbatim() throws {
        #expect(try parse(["hook", "codex", #"{"type":"agent-turn-complete"}"#, "--quiet", "-x"])
            == NotchctlCommand(action: .hook(adapter: "codex", arguments: [#"{"type":"agent-turn-complete"}"#, "--quiet", "-x"]), quiet: false))
        #expect(try parse(["-q", "hook", "claude-code"]) == NotchctlCommand(action: .hook(adapter: "claude-code", arguments: []), quiet: true))
        #expect(try parse(["hook"]).action == .hook(adapter: nil, arguments: []))
    }

    @Test func parsesPing() throws {
        #expect(try parse(["ping"]) == NotchctlCommand(action: .ping))
        #expect(throws: NotchctlUsageError.unexpectedArgument("now")) { try parse(["ping", "now"]) }
    }

    @Test func quietWorksBeforeAndAfterTheCommand() throws {
        #expect(try parse(["-q", "ping"]).quiet)
        #expect(try parse(["--quiet", "agent", "start", "--provider", "x"]).quiet)
        #expect(try parse(["agent", "start", "--provider", "x", "-q"]).quiet)
        #expect(try parse(["send", "--quiet", "{}"]).quiet)
        #expect(try parse(["ping", "--quiet"]).quiet)
        #expect(try !parse(["ping"]).quiet)
    }

    @Test func parsesHelpAndVersion() throws {
        for arguments in [["help"], ["--help"], ["-h"], ["-q", "--help"], ["agent", "--help"], ["agent", "start", "-h"], ["send", "--help"], ["ping", "-h"]] {
            #expect(try parse(arguments).action == .help)
        }
        #expect(try parse(["--version"]).action == .version)
        #expect(try parse(["version"]).action == .version)
    }

    @Test func rejectsMissingOrUnknownCommands() {
        #expect(throws: NotchctlUsageError.missingCommand) { try parse([]) }
        #expect(throws: NotchctlUsageError.missingCommand) { try parse(["-q"]) }
        #expect(throws: NotchctlUsageError.unknownCommand("activity")) { try parse(["activity", "start"]) }
        #expect(throws: NotchctlUsageError.unknownOption("--verbose")) { try parse(["--verbose", "ping"]) }
    }

    @Test func usageErrorsPrintSafely() {
        let description = NotchctlUsageError.unknownCommand("evil\u{1B}[2J\ncommand").description
        #expect(!description.contains("\n"))
        #expect(!description.contains("\u{1B}"))
    }

    // MARK: Output

    @Test func mapsClientErrorsToExitCodes() {
        #expect(NotchctlExitCode.forClientError(.invalidMessage(.malformed)) == .invalidMessage)
        #expect(NotchctlExitCode.forClientError(.notRunning).rawValue == 69)
        #expect(NotchctlExitCode.forClientError(.timedOut).rawValue == 69)
        #expect(NotchctlExitCode.forClientError(.socketPathTooLong).rawValue == 69)
        #expect(NotchctlExitCode.forClientError(.invalidResponse).rawValue == 70)
        #expect(NotchctlExitCode.forClientError(.connectionFailed(code: EACCES)).rawValue == 70)
        #expect([NotchctlExitCode.success, .usage, .invalidMessage].map(\.rawValue) == [0, 64, 65])
    }

    @Test func helpListsCommandsEventsAndExitCodes() {
        let help = NotchctlHelp.text(adapterNames: ["claude-code", "codex"])
        for event in NotchctlAgentEvent.allCases {
            #expect(help.contains(event.rawValue))
        }
        for word in ["send", "hook", "ping", "--provider", "--app", "--quiet", "--version", "claude-code, codex", "64", "65", "69", "70"] {
            #expect(help.contains(word))
        }
        #expect(NotchctlHelp.text(adapterNames: []).contains("(none)"))
    }
}
