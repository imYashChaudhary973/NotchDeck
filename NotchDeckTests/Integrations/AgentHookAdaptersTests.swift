import Foundation
import Testing
@testable import NotchDeck

struct AgentHookAdaptersTests {
    // MARK: Registry

    @Test func adaptersAreFoundByNameIgnoringCase() {
        #expect(AgentHookAdapters.adapter(named: "claude-code") is ClaudeCodeHookAdapter)
        #expect(AgentHookAdapters.adapter(named: "Claude-Code") is ClaudeCodeHookAdapter)
        #expect(AgentHookAdapters.adapter(named: "CODEX") is CodexHookAdapter)
        #expect(AgentHookAdapters.adapter(named: "codex-notify") is CodexNotifyAdapter)
        #expect(AgentHookAdapters.adapter(named: "claude") == nil)
        #expect(AgentHookAdapters.adapter(named: "") == nil)
    }

    @Test func adapterNamesAreUniqueLowercaseProviderStyleIDs() throws {
        let names = AgentHookAdapters.all.map(\.name)
        #expect(Set(names).count == names.count)
        for name in names {
            // Usable as a provider ID, so a name is also a valid `provider`.
            let message = try DeveloperBridgeMessage(provider: name, status: .working).validated()
            #expect(message.provider == name)
        }
    }

    @Test func onlyHookAdaptersReadStandardInput() {
        let reading = AgentHookAdapters.all.filter(\.readsStandardInput).map(\.name)
        #expect(reading.sorted() == ["claude-code", "codex"])
    }

    // MARK: Shared helpers

    @Test func payloadsMustBeJSONObjects() throws {
        #expect(throws: AgentHookError.unreadablePayload) { try AgentHookPayload(json: Data()) }
        #expect(throws: AgentHookError.unreadablePayload) { try AgentHookPayload(json: Data("[\"a\"]".utf8)) }
        let payload = try AgentHookPayload(json: Data(#"{"a": "x", "b": "", "c": 3, "d": ["y", 4, "z"]}"#.utf8))
        #expect(payload.string("a") == "x")
        #expect(payload.string("b") == nil)
        #expect(payload.string("c") == nil)
        #expect(payload.string("missing") == nil)
        #expect(payload.strings("d") == ["y", "z"])
        #expect(payload.strings("a").isEmpty)
    }

    @Test func taskLinesComeFromTheFirstNonEmptyLine() {
        #expect(AgentHookText.taskLine(fromPrompt: "  \n\t Fix the build \r\nmore") == "Fix the build")
        #expect(AgentHookText.taskLine(fromPrompt: "/review-pr 42") == "/review-pr 42")
        #expect(AgentHookText.taskLine(fromPrompt: "<task-notification>done</task-notification>") == nil)
        #expect(AgentHookText.taskLine(fromPrompt: " \n ") == nil)
        #expect(AgentHookText.taskLine(fromPrompt: nil) == nil)
    }

    @Test func toolLabelsNeverContainArbitraryText() {
        #expect(AgentToolActivity.label(forTool: "Bash") == "Bash")
        #expect(AgentToolActivity.label(forTool: "mcp__github__create_issue") == "github")
        #expect(AgentToolActivity.label(forTool: "mcp__") == "a tool")
        #expect(AgentToolActivity.label(forTool: "mcp__bad server__x") == "a tool")
        #expect(AgentToolActivity.label(forTool: "rm -rf /") == "a tool")
        #expect(AgentToolActivity.label(forTool: String(repeating: "x", count: 41)) == "a tool")
        #expect(AgentToolActivity.label(forTool: nil) == "a tool")
        #expect(AgentToolActivity.update(forTool: nil) == .status(.working))
        #expect(AgentToolActivity.update(forTool: "Bash") == .status(.runningCommand))
    }

    @Test func contextsDropValuesTheProtocolWouldReject() {
        let context = AgentHookContext(
            provider: "tool", providerName: "Tool",
            session: "bad session", workspace: "/tmp/x\u{7}y", environment: ["__CFBundleIdentifier": "nodots"]
        )
        #expect(context.session == nil)
        #expect(context.workspace == nil)
        #expect(context.terminal == nil)
        #expect(AgentHookContext.isValidWorkspace("/" + String(repeating: "a", count: DeveloperProtocol.maxPathLength)) == false)
        #expect(AgentHookContext.isValidSession("thr_123"))
        #expect(AgentHookContext.isValidSession("a:b@c+d=e/f.g-h"))
    }

    @Test func contextsBuildValidatedMessages() throws {
        let context = AgentHookContext(
            provider: "tool", providerName: "Tool", session: "s1", workspace: "/Users/me/Rove/../Rove", environment: [:]
        )
        #expect(context.messages(for: nil).isEmpty)

        let event = try #require(context.messages(for: .status(.waiting, message: "line one\nline two")).first)
        #expect(event.type == .event)
        #expect(event.status == .waiting)
        #expect(event.message == "line one line two")
        #expect(event.workspace == "/Users/me/Rove")
        #expect(event.isValidated)

        let end = try #require(context.messages(for: .end).first)
        #expect(end.type == .end)
        #expect(end.status == nil)
        #expect(end.sessionKey == "tool|session:s1")
    }

    @Test func optionsIgnoreUnknownArguments() {
        #expect(AgentHookOptions(arguments: []).promptAsTask == false)
        #expect(AgentHookOptions(arguments: ["--verbose", "--prompt-as-task"]).promptAsTask)
        #expect(AgentHookOptions(arguments: ["--prompt-as-task=yes"]).promptAsTask == false)
    }
}
