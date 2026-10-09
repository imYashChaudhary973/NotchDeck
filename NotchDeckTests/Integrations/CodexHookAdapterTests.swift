import Foundation
import Testing
@testable import NotchDeck

/// Sample payloads follow the Codex hooks reference (learn.chatgpt.com/docs/hooks), the hook
/// schemas in openai/codex (codex-rs/hooks/schema/generated) and the legacy notify payload
/// (codex-rs/hooks/src/legacy_notify.rs), checked 2026-10-09 against Codex 0.162.0. Private
/// content is marked SECRET.
struct CodexHookAdapterTests {
    let adapter = CodexHookAdapter()
    let session = "019a3c5e-7b1d-7f20-8e4a-2c6b9d0e1f3a"

    func payload(_ event: String, _ fields: String = "") -> String {
        """
        {"session_id": "\(session)",
         "transcript_path": "/Users/me/.codex/sessions/2026/10/09/SECRET-rollout.jsonl",
         "cwd": "/Users/me/ZenVoice",
         "hook_event_name": "\(event)",
         "model": "gpt-5.5-codex",
         "permission_mode": "default",
         "turn_id": "12"\(fields.isEmpty ? "" : ", " + fields)}
        """
    }

    func messages(_ json: String, arguments: [String] = [], environment: [String: String] = [:]) throws -> [DeveloperBridgeMessage] {
        try adapter.messages(for: hookInput(json, arguments: arguments, environment: environment))
    }

    func single(_ json: String, arguments: [String] = [], environment: [String: String] = [:]) throws -> DeveloperBridgeMessage {
        let result = try messages(json, arguments: arguments, environment: environment)
        try #require(result.count == 1)
        return result[0]
    }

    // MARK: Hooks

    @Test func promptSubmitReportsWorkingWithoutThePrompt() throws {
        let message = try single(payload("UserPromptSubmit", #""prompt": "SECRET rename foo to bar""#))
        #expect(message.provider == "codex")
        #expect(message.providerName == "Codex")
        #expect(message.session == session)
        #expect(message.workspace == "/Users/me/ZenVoice")
        #expect(message.status == .working)
        #expect(message.task == nil)

        let optedIn = try single(payload("UserPromptSubmit", #""prompt": "Rename foo to bar\nSECRET""#), arguments: ["--prompt-as-task"])
        #expect(optedIn.task == "Rename foo to bar")
    }

    @Test func toolsAreDescribedByNameOnly() throws {
        let bash = try single(payload("PreToolUse", #""tool_name": "Bash", "tool_use_id": "call_1", "tool_input": {"command": "SECRET deploy"}"#))
        #expect(bash.status == .runningCommand)
        #expect(bash.message == nil)

        let patch = try single(payload("PreToolUse", #""tool_name": "apply_patch", "tool_input": {"command": "*** Begin Patch SECRET"}"#))
        #expect(patch.status == .working)
        #expect(patch.message == "Editing files")

        let plan = try single(payload("PreToolUse", #""tool_name": "update_plan", "tool_input": {"plan": "SECRET"}"#))
        #expect(plan.message == "Updating the plan")

        let mcp = try single(payload("PreToolUse", #""tool_name": "mcp__filesystem__read_file", "tool_input": {"path": "/SECRET"}"#))
        #expect(mcp.message == "Using filesystem")
    }

    @Test func approvalRequestsNeedPermission() throws {
        let bash = try single(payload("PermissionRequest", #""tool_name": "Bash", "tool_input": {"command": "SECRET", "description": "SECRET reason"}"#))
        #expect(bash.status == .needsPermission)
        #expect(bash.message == "Codex needs your approval to run a command")

        #expect(try single(payload("PermissionRequest", #""tool_name": "apply_patch""#)).message == "Codex needs your approval to edit files")
        #expect(try single(payload("PermissionRequest", #""tool_name": "mcp__github__merge""#)).message == "Codex needs your approval to use github")
        #expect(try single(payload("PermissionRequest", #""tool_name": "network""#)).message == "Codex needs your approval")
        #expect(try single(payload("PermissionRequest")).message == "Codex needs your approval")
    }

    @Test func finishedToolsReturnToWorking() throws {
        let message = try single(payload("PostToolUse", #""tool_name": "Bash", "tool_input": {"command": "SECRET"}, "tool_response": "SECRET output""#))
        #expect(message.status == .working)
        #expect(message.message == nil)
    }

    @Test func turnsCompleteOrAreCancelled() throws {
        let stop = try single(payload("Stop", #""stop_hook_active": false, "last_assistant_message": "SECRET done""#))
        #expect(stop.status == .completed)
        #expect(stop.message == nil)

        #expect(try single(payload("Interrupt")).status == .cancelled)
    }

    @Test func sessionEndEndsTheSession() throws {
        let json = #"{"session_id": "thr_123", "transcript_path": null, "cwd": "/workspace", "hook_event_name": "SessionEnd", "reason": "other"}"#
        let message = try single(json)
        #expect(message.type == .end)
        #expect(message.session == "thr_123")
        #expect(message.workspace == "/workspace")
    }

    @Test func automaticCompactionIsWorkOtherEventsSendNothing() throws {
        #expect(try single(payload("PreCompact", #""trigger": "auto""#)).message == "Compacting conversation")
        let ignored = [
            payload("PreCompact", #""trigger": "manual""#),
            payload("PostCompact", #""trigger": "auto""#),
            payload("SessionStart", #""source": "startup""#),
            payload("SubagentStart", #""agent_id": "a1", "agent_type": "explorer""#),
            payload("SubagentStop", #""agent_id": "a1", "agent_type": "explorer", "last_assistant_message": "SECRET""#),
            payload("FutureEvent"),
        ]
        for json in ignored {
            #expect(try messages(json).isEmpty)
        }
    }

    @Test func unreadablePayloadsThrow() {
        for json in ["", "{", "[]", "null"] {
            #expect(throws: AgentHookError.unreadablePayload) { try messages(json) }
        }
    }

    @Test func relativeWorkingDirectoriesAndInvalidSessionsAreOmitted() throws {
        let json = #"{"session_id": "bad id", "cwd": "workspace", "hook_event_name": "Stop"}"#
        let message = try single(json)
        #expect(message.session == nil)
        #expect(message.workspace == nil)
        #expect(message.sessionKey == "codex|default")
    }

    @Test func theTerminalComesFromTheEnvironment() throws {
        #expect(try single(payload("Stop"), environment: ["TERM_PROGRAM": "ghostty"]).terminal == "com.mitchellh.ghostty")
    }

    @Test func everyHookMessageIsValidAndPrivate() throws {
        let samples = [
            payload("UserPromptSubmit", #""prompt": "SECRET""#),
            payload("PreToolUse", #""tool_name": "Bash", "tool_input": {"command": "SECRET"}"#),
            payload("PermissionRequest", #""tool_name": "Bash", "tool_input": {"command": "SECRET", "description": "SECRET"}"#),
            payload("PostToolUse", #""tool_name": "Bash", "tool_response": "SECRET""#),
            payload("PreCompact", #""trigger": "auto""#),
            payload("Stop", #""last_assistant_message": "SECRET""#),
            payload("Interrupt"),
            payload("SessionEnd", #""reason": "other""#),
        ]
        for (index, json) in samples.enumerated() {
            let message = try single(json, environment: ["TERM_PROGRAM": "vscode"])
            #expect(message.isValidated, "sample \(index)")
            #expect(message.provider == "codex")
            #expect(message.terminal == "com.microsoft.VSCode")
            #expect(!message.allText.contains { $0.contains("SECRET") }, "sample \(index): \(message.allText)")
        }
    }

    // MARK: Legacy notify

    let notify = CodexNotifyAdapter()

    func notifyPayload(type: String = "agent-turn-complete") -> String {
        """
        {"type": "\(type)", "thread-id": "b5f6c1c2-1111-2222-3333-444455556666", "turn-id": "12345",
         "cwd": "/Users/me/ZenVoice", "client": "codex-tui",
         "input-messages": ["Rename `foo` to `bar`.\\nSECRET details"],
         "last-assistant-message": "SECRET Rename complete."}
        """
    }

    @Test func notifyReportsACompletedTurnWithoutItsMessages() throws {
        let result = try notify.messages(for: AgentHookInput(arguments: [notifyPayload()], environment: ["TERM_PROGRAM": "iTerm.app"]))
        let message = try #require(result.first)
        #expect(result.count == 1)
        #expect(message.provider == "codex")
        #expect(message.providerName == "Codex")
        #expect(message.status == .completed)
        #expect(message.session == "b5f6c1c2-1111-2222-3333-444455556666")
        #expect(message.workspace == "/Users/me/ZenVoice")
        #expect(message.terminal == "com.googlecode.iterm2")
        #expect(message.task == nil)
        #expect(message.isValidated)
        #expect(!message.allText.contains { $0.contains("SECRET") })
    }

    @Test func notifyCanUseTheFirstInputMessageAsTheTask() throws {
        let result = try notify.messages(for: AgentHookInput(arguments: ["--prompt-as-task", notifyPayload()]))
        #expect(result.first?.task == "Rename `foo` to `bar`.")
    }

    @Test func notifyIgnoresOtherTypesAndRejectsMissingPayloads() throws {
        #expect(try notify.messages(for: AgentHookInput(arguments: [notifyPayload(type: "approval-requested")])).isEmpty)
        #expect(throws: AgentHookError.unreadablePayload) { try notify.messages(for: AgentHookInput()) }
        #expect(throws: AgentHookError.unreadablePayload) { try notify.messages(for: AgentHookInput(arguments: ["--prompt-as-task"])) }
        #expect(throws: AgentHookError.unreadablePayload) { try notify.messages(for: AgentHookInput(arguments: ["{not json"])) }
    }

    @Test func notifyNeverReadsStandardInput() throws {
        #expect(!notify.readsStandardInput)
        #expect(adapter.readsStandardInput)
        // Even if something arrives there, only the argument counts.
        let input = AgentHookInput(standardInput: Data(payload("Interrupt").utf8), arguments: [notifyPayload()])
        #expect(try notify.messages(for: input).first?.status == .completed)
    }

    @Test func theHookAdapterAcceptsANotifyPayloadToo() throws {
        // notify = ["notchctl", "hook", "codex"]: nothing on standard input, payload as the last argument.
        let result = try adapter.messages(for: AgentHookInput(arguments: [notifyPayload()]))
        #expect(result.first?.status == .completed)
        #expect(result.first?.session == "b5f6c1c2-1111-2222-3333-444455556666")
    }
}
