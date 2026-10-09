import Foundation

/// Translates Claude Code hook events into developer activity: `notchctl hook claude-code`, set
/// up as a command hook in Claude Code's `settings.json` (see docs/integrations/claude-code.md).
///
/// Claude Code passes each event as JSON on standard input. The adapter reads only the event
/// name, the session ID, the working directory, tool names, notification types and Claude's own
/// notification text. Prompts, tool input and output, and transcripts are never forwarded; with
/// `--prompt-as-task` the first line of each prompt becomes the session's task.
///
/// | Event | Reported as |
/// | --- | --- |
/// | `UserPromptSubmit` | working |
/// | `PreToolUse` | running a command (`Bash`, `PowerShell`), needs input (`AskUserQuestion`, `ExitPlanMode`), otherwise working ("Editing files") |
/// | `PermissionRequest` | needs permission |
/// | `PostToolUse`, `PostToolUseFailure`, `ElicitationResult` | working |
/// | `Notification` | see `ClaudeCodeNotification` |
/// | `Elicitation` | needs input |
/// | `PreCompact` (auto) | working ("Compacting conversation") |
/// | `Stop` | completed |
/// | `StopFailure` | failed |
/// | `SessionEnd` | end |
///
/// Everything else — `SessionStart` (an idle session shouldn't occupy the notch before the first
/// prompt), `SubagentStart`/`SubagentStop` (they also fire for Claude Code's internal agents
/// after a turn), a manual `PreCompact`, `PostCompact` and any event newer than this adapter —
/// sends nothing.
struct ClaudeCodeHookAdapter: AgentHookAdapter {
    static let provider = "claude-code"
    static let providerName = "Claude Code"

    let name = Self.provider
    let readsStandardInput = true

    func messages(for input: AgentHookInput) throws -> [DeveloperBridgeMessage] {
        let payload = try AgentHookPayload(json: input.standardInput)
        let context = AgentHookContext(
            provider: Self.provider,
            providerName: Self.providerName,
            session: payload.string("session_id"),
            workspace: Self.workspace(payload: payload, environment: input.environment),
            environment: input.environment
        )
        return context.messages(for: update(for: payload, options: AgentHookOptions(arguments: input.arguments)))
    }

    /// What an event means for the session; nil for events that change nothing.
    func update(for payload: AgentHookPayload, options: AgentHookOptions) -> AgentHookUpdate? {
        switch payload.string("hook_event_name") {
        case "UserPromptSubmit":
            let prompt = options.promptAsTask ? AgentHookText.taskLine(fromPrompt: payload.string("prompt")) : nil
            // A custom session title (`--name`, `/rename`) is a label the user chose for the session.
            return .status(.working, task: prompt ?? payload.string("session_title"))
        case "PreToolUse":
            let tool = payload.string("tool_name")
            return Self.interactiveToolUpdate(tool) ?? AgentToolActivity.update(forTool: tool)
        case "PermissionRequest":
            let tool = payload.string("tool_name")
            return Self.interactiveToolUpdate(tool)
                ?? .status(.needsPermission, message: "Claude needs your permission to use \(AgentToolActivity.label(forTool: tool))")
        case "PostToolUse", "PostToolUseFailure", "ElicitationResult":
            return .status(.working)
        case "Notification":
            return ClaudeCodeNotification(type: payload.string("notification_type"), message: payload.string("message")).update
        case "Elicitation":
            let server = AgentToolActivity.label(forServer: payload.string("mcp_server_name"))
            return .status(.needsInput, message: server.map { "\($0) needs your input" } ?? "An MCP server needs your input")
        case "PreCompact":
            // A manual /compact happens between turns and is followed by no Stop event, so it
            // would leave the session "working".
            return payload.string("trigger") == "auto" ? .status(.working, message: "Compacting conversation") : nil
        case "Stop":
            return .status(.completed)
        case "StopFailure":
            return .status(.failed, message: Self.failureMessage(forError: payload.string("error")))
        case "SessionEnd":
            return .end
        default:
            return nil
        }
    }

    /// The project directory: `CLAUDE_PROJECT_DIR`, which Claude Code exports to hooks and which
    /// stays put when Claude changes directory, otherwise the event's `cwd`.
    static func workspace(payload: AgentHookPayload, environment: [String: String]) -> String? {
        if let projectDirectory = environment["CLAUDE_PROJECT_DIR"], AgentHookContext.isValidWorkspace(projectDirectory) {
            return projectDirectory
        }
        return payload.string("cwd")
    }

    /// Tools that wait for the user rather than for a permission decision: Claude asking a
    /// question, or presenting a plan for approval.
    static func interactiveToolUpdate(_ tool: String?) -> AgentHookUpdate? {
        switch tool {
        case "AskUserQuestion": .status(.needsInput, message: "Claude has a question")
        case "ExitPlanMode": .status(.needsInput, message: "Claude's plan is ready for review")
        default: nil
        }
    }

    /// A short description of a `StopFailure` error type. The API's own error text isn't
    /// forwarded.
    static func failureMessage(forError error: String?) -> String {
        switch error {
        case "rate_limit": "Rate limit reached"
        case "overloaded": "The API is overloaded"
        case "authentication_failed", "oauth_org_not_allowed", "cloud_credential_error": "Authentication failed"
        case "billing_error": "Billing problem"
        case "account_on_hold": "Account on hold"
        case "max_output_tokens": "Response reached the output limit"
        case "model_not_found": "Model not available"
        case "invalid_request": "Invalid request"
        case "server_error": "API server error"
        default: "API error"
        }
    }
}

/// What a Claude Code `Notification` hook means.
///
/// The version-specific part of the Claude Code adapter. Claude Code v2.0.37 added
/// `notification_type`; earlier versions sent only the text — "Claude needs your permission to
/// use Bash" or, when idle, "Claude is waiting for your input" — so their permission prompts are
/// recognized by the text.
///
/// Ignored: `idle_prompt` (sent about a minute after a turn completed; `Stop` already reported
/// that, and a reminder would keep "needs you" on the notch for a session you walked away from),
/// `auth_success`, `agent_needs_input`/`agent_completed` (about background sessions, which report
/// through their own hooks), `quota_auto_resume_disabled` and unknown types.
enum ClaudeCodeNotification: Equatable, Sendable {
    /// `permission_prompt`: a tool use or network request waits for approval.
    case needsPermission(message: String?)
    /// `elicitation_dialog`, `elicitation_url_dialog`, `quota_auto_resume_stale`: waits for an answer.
    case needsInput(message: String?)
    /// `elicitation_complete`, `elicitation_response`, `quota_auto_resume_fired`: work continues.
    case resumed
    case ignored

    init(type: String?, message: String?) {
        guard let type else {
            self = Self.legacy(message: message)
            return
        }
        switch type {
        case "permission_prompt":
            self = .needsPermission(message: message)
        case "elicitation_dialog", "elicitation_url_dialog", "quota_auto_resume_stale":
            self = .needsInput(message: message)
        case "elicitation_complete", "elicitation_response", "quota_auto_resume_fired":
            self = .resumed
        default:
            self = .ignored
        }
    }

    /// Versions before notification types.
    private static func legacy(message: String?) -> Self {
        guard let message, message.localizedCaseInsensitiveContains("permission") else { return .ignored }
        return .needsPermission(message: message)
    }

    var update: AgentHookUpdate? {
        switch self {
        case .needsPermission(let message): .status(.needsPermission, message: message ?? "Claude needs your permission")
        case .needsInput(let message): .status(.needsInput, message: message ?? "Claude needs your input")
        case .resumed: .status(.working)
        case .ignored: nil
        }
    }
}
