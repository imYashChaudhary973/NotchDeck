import Foundation
import Testing
@testable import NotchDeck

/// Sample payloads follow the Claude Code hooks reference (code.claude.com/docs/en/hooks,
/// checked 2026-10-09, Claude Code 2.1.295). Private content is marked SECRET so the privacy
/// tests can look for it.
struct ClaudeCodeHookAdapterTests {
    let adapter = ClaudeCodeHookAdapter()
    let session = "8f1c2a7e-3b4d-4e5f-9a0b-1c2d3e4f5a6b"

    func payload(_ event: String, _ fields: String = "") -> String {
        """
        {"session_id": "\(session)",
         "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
         "transcript_path": "/Users/me/.claude/projects/-Users-me-Rove/SECRET-transcript.jsonl",
         "cwd": "/Users/me/Rove",
         "permission_mode": "default",
         "hook_event_name": "\(event)"\(fields.isEmpty ? "" : ", " + fields)}
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

    // MARK: Turns

    @Test func promptSubmitReportsWorkingWithoutThePrompt() throws {
        let message = try single(payload("UserPromptSubmit", #""prompt": "SECRET Fix the login bug in ~/Clients/Acme""#))

        #expect(message.type == .event)
        #expect(message.provider == "claude-code")
        #expect(message.providerName == "Claude Code")
        #expect(message.session == session)
        #expect(message.workspace == "/Users/me/Rove")
        #expect(message.status == .working)
        #expect(message.task == nil)
        #expect(message.message == nil)
    }

    @Test func promptAsTaskUsesTheFirstLineOfThePrompt() throws {
        let json = payload("UserPromptSubmit", #""prompt": "\n   Implement tab management  \nSECRET details on the second line""#)
        let message = try single(json, arguments: ["--prompt-as-task"])
        #expect(message.task == "Implement tab management")
    }

    @Test func promptAsTaskIsTruncatedByTheProtocol() throws {
        let long = String(repeating: "a", count: 1_000)
        let message = try single(payload("UserPromptSubmit", #""prompt": "\#(long)""#), arguments: ["--prompt-as-task"])
        let task = try #require(message.task)
        #expect(task.count == DeveloperProtocol.maxTextLength)
        #expect(task.hasSuffix("…"))
    }

    @Test func promptAsTaskSkipsPastedAndGeneratedPrompts() throws {
        let pasted = payload("UserPromptSubmit", #""prompt": "<pasted_content id=\"1\">\nSECRET token\n</pasted_content id=\"1\">""#)
        let message = try single(pasted, arguments: ["--prompt-as-task"])
        #expect(message.status == .working)
        #expect(message.task == nil)
    }

    @Test func aCustomSessionTitleBecomesTheTask() throws {
        let json = payload("UserPromptSubmit", #""prompt": "SECRET", "session_title": "auth-refactor""#)
        #expect(try single(json).task == "auth-refactor")
        // The prompt wins when the user opted in.
        let withPrompt = payload("UserPromptSubmit", #""prompt": "Add OAuth", "session_title": "auth-refactor""#)
        #expect(try single(withPrompt, arguments: ["--prompt-as-task"]).task == "Add OAuth")
    }

    @Test func stopCompletesWithoutForwardingClaudesAnswer() throws {
        let json = payload("Stop", """
            "stop_hook_active": false,
            "last_assistant_message": "SECRET I've completed the refactoring.",
            "background_tasks": [], "session_crons": []
            """)
        let message = try single(json)
        #expect(message.status == .completed)
        #expect(message.message == nil)
    }

    @Test func stopFailureReportsAFixedDescriptionOfTheError() throws {
        let json = payload("StopFailure", #""error": "rate_limit", "error_details": "SECRET 429", "last_assistant_message": "SECRET API Error""#)
        let message = try single(json)
        #expect(message.status == .failed)
        #expect(message.message == "Rate limit reached")

        let unknown = try single(payload("StopFailure", #""error": "something_new""#))
        #expect(unknown.message == "API error")
    }

    @Test func sessionEndEndsTheSession() throws {
        let message = try single(payload("SessionEnd", #""reason": "prompt_input_exit""#))
        #expect(message.type == .end)
        #expect(message.status == nil)
        #expect(message.session == session)
    }

    // MARK: Tools

    @Test func shellToolsRunACommandWithoutForwardingIt() throws {
        let json = payload("PreToolUse", """
            "tool_name": "Bash",
            "tool_input": {"command": "rm -rf ~/SECRET-project", "description": "SECRET cleanup"},
            "tool_use_id": "toolu_01ABC123"
            """)
        let message = try single(json)
        #expect(message.status == .runningCommand)
        #expect(message.message == nil)

        #expect(try single(payload("PreToolUse", #""tool_name": "PowerShell""#)).status == .runningCommand)
    }

    @Test func otherToolsAreDescribedByName() throws {
        func describe(_ tool: String) throws -> DeveloperBridgeMessage {
            try single(payload("PreToolUse", #""tool_name": "\#(tool)", "tool_input": {"file_path": "/Users/me/Rove/SECRET.swift"}"#))
        }
        #expect(try describe("Edit").message == "Editing files")
        #expect(try describe("Write").message == "Editing files")
        #expect(try describe("Read").message == "Reading files")
        #expect(try describe("Grep").message == "Searching files")
        #expect(try describe("Agent").message == "Running a subagent")
        #expect(try describe("Task").message == "Running a subagent")
        #expect(try describe("mcp__github__create_issue").message == "Using github")
        #expect(try describe("Workflow").message == "Using Workflow")
        #expect(try describe("Edit").status == .working)
    }

    @Test func questionsAndPlansNeedInput() throws {
        let question = try single(payload("PreToolUse", #""tool_name": "AskUserQuestion", "tool_input": {"questions": [{"question": "SECRET?"}]}"#))
        #expect(question.status == .needsInput)
        #expect(question.message == "Claude has a question")

        let plan = try single(payload("PermissionRequest", #""tool_name": "ExitPlanMode", "tool_input": {"plan": "SECRET plan"}"#))
        #expect(plan.status == .needsInput)
        #expect(plan.message == "Claude's plan is ready for review")
    }

    @Test func permissionRequestsNeedPermissionWithoutForwardingTheInput() throws {
        let json = payload("PermissionRequest", """
            "tool_name": "Bash",
            "tool_input": {"command": "rm -rf SECRET", "description": "SECRET"},
            "permission_suggestions": [{"type": "addRules", "rules": [{"toolName": "Bash", "ruleContent": "rm -rf SECRET"}],
                                        "behavior": "allow", "destination": "localSettings"}]
            """)
        let message = try single(json)
        #expect(message.status == .needsPermission)
        #expect(message.message == "Claude needs your permission to use Bash")

        let mcp = try single(payload("PermissionRequest", #""tool_name": "mcp__memory__write""#))
        #expect(mcp.message == "Claude needs your permission to use memory")
    }

    @Test func finishedToolsReturnToWorking() throws {
        let success = payload("PostToolUse", """
            "tool_name": "Write",
            "tool_input": {"file_path": "/Users/me/Rove/SECRET.txt", "content": "SECRET"},
            "tool_response": {"filePath": "/Users/me/Rove/SECRET.txt", "type": "create"},
            "tool_use_id": "toolu_01ABC123", "duration_ms": 12
            """)
        let failure = payload("PostToolUseFailure", """
            "tool_name": "Bash", "tool_input": {"command": "npm test"},
            "error": "Exit code 1\\nSECRET output", "is_interrupt": false
            """)
        for json in [success, failure] {
            let message = try single(json)
            #expect(message.status == .working)
            #expect(message.message == nil)
        }
    }

    // MARK: Notifications

    @Test func permissionPromptNotificationsNeedPermission() throws {
        let json = payload("Notification", #""message": "Claude needs your permission to use Bash", "title": "Permission needed", "notification_type": "permission_prompt""#)
        let message = try single(json)
        #expect(message.status == .needsPermission)
        #expect(message.message == "Claude needs your permission to use Bash")
    }

    @Test func elicitationNotificationsNeedInput() throws {
        let json = payload("Notification", #""message": "Claude Code needs your input", "notification_type": "elicitation_dialog""#)
        #expect(try single(json).status == .needsInput)
        let resumed = payload("Notification", #""message": "Response sent", "notification_type": "elicitation_response""#)
        #expect(try single(resumed).status == .working)
    }

    @Test func idleAuthBackgroundAndUnknownNotificationsAreIgnored() throws {
        for type in ["idle_prompt", "auth_success", "agent_needs_input", "agent_completed", "quota_auto_resume_disabled", "brand_new_type"] {
            let json = payload("Notification", #""message": "Claude is waiting for your input", "notification_type": "\#(type)""#)
            #expect(try messages(json).isEmpty, "\(type)")
        }
    }

    @Test func notificationsWithoutATypeFallBackToTheText() throws {
        // Claude Code before v2.0.37 sent no notification_type.
        let permission = payload("Notification", #""message": "Claude needs your permission to use Bash""#)
        #expect(try single(permission).status == .needsPermission)

        let idle = payload("Notification", #""message": "Claude is waiting for your input""#)
        #expect(try messages(idle).isEmpty)
        #expect(try messages(payload("Notification")).isEmpty)
    }

    @Test func notificationKindsAreIsolated() {
        #expect(ClaudeCodeNotification(type: "permission_prompt", message: nil).update == .status(.needsPermission, message: "Claude needs your permission"))
        #expect(ClaudeCodeNotification(type: "quota_auto_resume_stale", message: nil).update == .status(.needsInput, message: "Claude needs your input"))
        #expect(ClaudeCodeNotification(type: "quota_auto_resume_fired", message: nil) == .resumed)
        #expect(ClaudeCodeNotification(type: nil, message: "Needs PERMISSION") == .needsPermission(message: "Needs PERMISSION"))
        #expect(ClaudeCodeNotification(type: nil, message: nil) == .ignored)
    }

    @Test func mcpElicitationsNeedInput() throws {
        let json = payload("Elicitation", """
            "mcp_server_name": "my-mcp-server", "message": "SECRET Please provide your credentials",
            "mode": "form", "requested_schema": {"type": "object"}
            """)
        let message = try single(json)
        #expect(message.status == .needsInput)
        #expect(message.message == "my-mcp-server needs your input")
        #expect(try single(payload("ElicitationResult", #""mcp_server_name": "my-mcp-server""#)).status == .working)
    }

    // MARK: Ignored events

    @Test func automaticCompactionIsWorkManualCompactionIsIgnored() throws {
        let auto = try single(payload("PreCompact", #""trigger": "auto", "custom_instructions": null"#))
        #expect(auto.status == .working)
        #expect(auto.message == "Compacting conversation")
        #expect(try messages(payload("PreCompact", #""trigger": "manual", "custom_instructions": "SECRET""#)).isEmpty)
        #expect(try messages(payload("PostCompact", #""trigger": "auto", "compact_summary": "SECRET""#)).isEmpty)
    }

    @Test func sessionStartSubagentsAndUnknownEventsSendNothing() throws {
        let ignored = [
            payload("SessionStart", #""source": "startup", "model": "claude-opus-5""#),
            payload("SubagentStart", #""agent_id": "agent-abc123", "agent_type": "Explore""#),
            payload("SubagentStop", #""agent_id": "def456", "agent_type": "", "last_assistant_message": "SECRET""#),
            payload("PermissionDenied", #""tool_name": "Bash", "reason": "[Irreversible Local Destruction]""#),
            payload("CwdChanged", #""old_cwd": "/a", "new_cwd": "/b""#),
            payload("SomeEventFrom2027"),
            #"{"session_id": "abc"}"#,
        ]
        for json in ignored {
            #expect(try messages(json).isEmpty)
        }
    }

    // MARK: Input handling

    @Test func unreadablePayloadsThrow() {
        for json in ["", "not json", "[1, 2]", "\"text\"", #"{"session_id": "abc""#] {
            #expect(throws: AgentHookError.unreadablePayload) { try messages(json) }
        }
    }

    @Test func fieldsWithUnexpectedTypesCountAsMissing() throws {
        let json = #"{"session_id": 42, "cwd": ["/x"], "hook_event_name": "PreToolUse", "tool_name": {"name": "Bash"}}"#
        let message = try single(json)
        #expect(message.status == .working)
        #expect(message.message == nil)
        #expect(message.session == nil)
        #expect(message.workspace == nil)
    }

    @Test func relativeOrMissingWorkingDirectoriesAreOmitted() throws {
        let relative = #"{"session_id": "abc", "cwd": "Rove/src", "hook_event_name": "Stop"}"#
        #expect(try single(relative).workspace == nil)
        let missing = #"{"session_id": "abc", "hook_event_name": "Stop"}"#
        #expect(try single(missing).workspace == nil)
    }

    @Test func theProjectDirectoryIsPreferredOverTheWorkingDirectory() throws {
        let json = payload("Stop").replacingOccurrences(of: "\"cwd\": \"/Users/me/Rove\"", with: "\"cwd\": \"/Users/me/Rove/Sources/App\"")
        #expect(try single(json, environment: ["CLAUDE_PROJECT_DIR": "/Users/me/Rove"]).workspace == "/Users/me/Rove")
        #expect(try single(json, environment: ["CLAUDE_PROJECT_DIR": "relative"]).workspace == "/Users/me/Rove/Sources/App")
        #expect(try single(json).workspace == "/Users/me/Rove/Sources/App")
    }

    @Test func invalidSessionIDsAreOmitted() throws {
        for id in ["has spaces", "semi;colon", String(repeating: "a", count: 200), "émoji"] {
            let json = #"{"session_id": "\#(id)", "cwd": "/Users/me/Rove", "hook_event_name": "Stop"}"#
            let message = try single(json)
            #expect(message.session == nil, "\(id)")
            // The workspace still identifies the session.
            #expect(message.sessionKey == "claude-code|workspace:/Users/me/Rove")
        }
    }

    @Test func theTerminalComesFromTheEnvironment() throws {
        let json = payload("Stop")
        #expect(try single(json, environment: ["TERM_PROGRAM": "iTerm.app"]).terminal == "com.googlecode.iterm2")
        let both = ["TERM_PROGRAM": "iTerm.app", "__CFBundleIdentifier": "com.mitchellh.ghostty"]
        #expect(try single(json, environment: both).terminal == "com.mitchellh.ghostty")
        #expect(try single(json, environment: ["TERM_PROGRAM": "tmux"]).terminal == nil)
        #expect(try single(json).terminal == nil)
    }

    @Test func unknownArgumentsAreIgnored() throws {
        let message = try single(payload("UserPromptSubmit", #""prompt": "Hello""#), arguments: ["--future-flag", "value"])
        #expect(message.status == .working)
        #expect(message.task == nil)
    }

    // MARK: Every message

    var samples: [String] {
        [
            payload("UserPromptSubmit", #""prompt": "SECRET prompt", "session_title": "Tabs""#),
            payload("PreToolUse", #""tool_name": "Bash", "tool_input": {"command": "SECRET"}"#),
            payload("PreToolUse", #""tool_name": "Edit", "tool_input": {"file_path": "/SECRET", "old_string": "SECRET"}"#),
            payload("PreToolUse", #""tool_name": "AskUserQuestion", "tool_input": {"questions": "SECRET"}"#),
            payload("PermissionRequest", #""tool_name": "WebFetch", "tool_input": {"url": "https://SECRET.example"}"#),
            payload("PostToolUse", #""tool_name": "Read", "tool_input": {"file_path": "/SECRET"}, "tool_response": "SECRET""#),
            payload("PostToolUseFailure", #""tool_name": "Bash", "error": "SECRET""#),
            payload("Notification", #""message": "Claude needs your permission to use Bash", "notification_type": "permission_prompt""#),
            payload("Elicitation", #""mcp_server_name": "github", "message": "SECRET""#),
            payload("PreCompact", #""trigger": "auto""#),
            payload("Stop", #""last_assistant_message": "SECRET""#),
            payload("StopFailure", #""error": "overloaded", "last_assistant_message": "SECRET""#),
            payload("SessionEnd", #""reason": "other""#),
        ]
    }

    @Test func everyMessageIsValidAndPrivate() throws {
        let environment = ["TERM_PROGRAM": "Apple_Terminal", "CLAUDE_PROJECT_DIR": "/Users/me/Rove"]
        for (index, json) in samples.enumerated() {
            let result = try messages(json, environment: environment)
            #expect(result.count == 1, "sample \(index)")
            for message in result {
                #expect(message.isValidated, "sample \(index)")
                #expect(message.provider == "claude-code")
                #expect(message.providerName == "Claude Code")
                #expect(message.terminal == "com.apple.Terminal")
                #expect(!message.allText.contains { $0.contains("SECRET") }, "sample \(index): \(message.allText)")
            }
        }
    }

    @Test func onlyTheOptInForwardsThePrompt() throws {
        let json = payload("UserPromptSubmit", #""prompt": "SECRET plan""#)
        #expect(try !single(json).allText.contains { $0.contains("SECRET") })
        #expect(try single(json, arguments: ["--prompt-as-task"]).task == "SECRET plan")
    }
}
