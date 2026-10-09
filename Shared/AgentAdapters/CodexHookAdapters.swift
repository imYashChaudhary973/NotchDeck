import Foundation

/// Translates Codex lifecycle hooks into developer activity: `notchctl hook codex`, set up as a
/// command hook in `~/.codex/hooks.json` or `[hooks]` in `~/.codex/config.toml` (Codex 0.124 and
/// later; see docs/integrations/codex.md).
///
/// Codex passes each event as JSON on standard input. The adapter reads only the event name, the
/// session ID, the working directory, tool names and the compaction trigger. Prompts, tool input
/// and output, and transcripts are never forwarded; with `--prompt-as-task` the first line of each
/// prompt becomes the session's task.
///
/// | Event | Reported as |
/// | --- | --- |
/// | `UserPromptSubmit` | working |
/// | `PreToolUse` | running a command (`Bash`), otherwise working ("Editing files") |
/// | `PermissionRequest` | needs permission |
/// | `PostToolUse` | working |
/// | `PreCompact` (auto) | working ("Compacting conversation") |
/// | `Stop` | completed |
/// | `Interrupt` (Codex 0.150+) | cancelled |
/// | `SessionEnd` (Codex 0.145+) | end |
///
/// `SessionStart`, `SubagentStart`, `SubagentStop`, a manual `PreCompact`, `PostCompact` and any
/// newer event send nothing.
///
/// A legacy `notify` payload passed as the last argument (with nothing on standard input) is
/// handed to `CodexNotifyAdapter`. That only helps with Codex versions that start the notify
/// program without standard input (0.100 and later); older ones hand it the terminal, which
/// `notchctl hook codex` would wait to read. The documented `notify` setup uses `codex-notify`.
struct CodexHookAdapter: AgentHookAdapter {
    static let provider = "codex"
    static let providerName = "Codex"

    let name = Self.provider
    let readsStandardInput = true

    func messages(for input: AgentHookInput) throws -> [DeveloperBridgeMessage] {
        if input.standardInput.isEmpty, CodexNotifyAdapter.payloadArgument(in: input.arguments) != nil {
            return try CodexNotifyAdapter().messages(for: input)
        }
        let payload = try AgentHookPayload(json: input.standardInput)
        let context = AgentHookContext(
            provider: Self.provider,
            providerName: Self.providerName,
            session: payload.string("session_id"),
            workspace: payload.string("cwd"),
            environment: input.environment
        )
        return context.messages(for: update(for: payload, options: AgentHookOptions(arguments: input.arguments)))
    }

    /// What an event means for the session; nil for events that change nothing.
    func update(for payload: AgentHookPayload, options: AgentHookOptions) -> AgentHookUpdate? {
        switch payload.string("hook_event_name") {
        case "UserPromptSubmit":
            let task = options.promptAsTask ? AgentHookText.taskLine(fromPrompt: payload.string("prompt")) : nil
            return .status(.working, task: task)
        case "PreToolUse":
            return AgentToolActivity.update(forTool: payload.string("tool_name"))
        case "PermissionRequest":
            return .status(.needsPermission, message: Self.approvalMessage(forTool: payload.string("tool_name")))
        case "PostToolUse":
            return .status(.working)
        case "PreCompact":
            // A manual /compact happens between turns and is followed by no Stop event.
            return payload.string("trigger") == "auto" ? .status(.working, message: "Compacting conversation") : nil
        case "Stop":
            return .status(.completed)
        case "Interrupt":
            return .status(.cancelled)
        case "SessionEnd":
            return .end
        default:
            return nil
        }
    }

    /// What Codex asks approval for, by tool name only; `tool_input` (including its
    /// `description`) can hold the command and isn't forwarded.
    static func approvalMessage(forTool tool: String?) -> String {
        switch tool {
        case "Bash": "Codex needs your approval to run a command"
        case "apply_patch": "Codex needs your approval to edit files"
        case let tool? where tool.hasPrefix("mcp__"): "Codex needs your approval to use \(AgentToolActivity.label(forTool: tool))"
        default: "Codex needs your approval"
        }
    }
}

/// Translates Codex's legacy `notify` program call into developer activity:
/// `notify = ["notchctl", "hook", "codex-notify"]` in `~/.codex/config.toml`.
///
/// Codex appends the payload, a JSON object, as the last argument and documents a single type,
/// `agent-turn-complete` (keys `thread-id`, `turn-id`, `cwd`, `client`, `input-messages`,
/// `last-assistant-message`). It is reported as completed. `last-assistant-message` is never
/// forwarded; `input-messages` only with `--prompt-as-task`. Other types send nothing.
///
/// Doesn't read standard input: older Codex versions (such as 0.20) start the notify program
/// with the terminal as its standard input. For anything beyond completion, use the
/// lifecycle hooks (`CodexHookAdapter`).
struct CodexNotifyAdapter: AgentHookAdapter {
    let name = "codex-notify"
    let readsStandardInput = false

    func messages(for input: AgentHookInput) throws -> [DeveloperBridgeMessage] {
        guard let argument = Self.payloadArgument(in: input.arguments) else { throw AgentHookError.unreadablePayload }
        let payload = try AgentHookPayload(json: Data(argument.utf8))
        let options = AgentHookOptions(arguments: input.arguments.dropLast())
        let context = AgentHookContext(
            provider: CodexHookAdapter.provider,
            providerName: CodexHookAdapter.providerName,
            session: payload.string("thread-id"),
            workspace: payload.string("cwd"),
            environment: input.environment
        )
        return context.messages(for: update(for: payload, options: options))
    }

    func update(for payload: AgentHookPayload, options: AgentHookOptions) -> AgentHookUpdate? {
        switch payload.string("type") {
        case "agent-turn-complete":
            let task = options.promptAsTask ? AgentHookText.taskLine(fromPrompt: payload.strings("input-messages").first) : nil
            return .status(.completed, task: task)
        default:
            return nil
        }
    }

    /// The last argument when it looks like a JSON object.
    static func payloadArgument(in arguments: [String]) -> String? {
        guard let last = arguments.last, last.drop(while: \.isWhitespace).hasPrefix("{") else { return nil }
        return last
    }
}
