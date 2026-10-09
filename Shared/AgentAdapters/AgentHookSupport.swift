import Foundation

// Building blocks shared by the tool adapters (ClaudeCodeHookAdapter, CodexHookAdapter,
// CodexNotifyAdapter). Nothing in this file knows a particular tool.

/// Why an adapter couldn't use a payload. `notchctl hook` stays silent and exits 0 either way.
enum AgentHookError: Error, Equatable, Sendable {
    /// The payload is missing or isn't a JSON object.
    case unreadablePayload
}

/// A tool's JSON payload, read leniently.
///
/// Only the top level has to be a JSON object. A field with an unexpected type counts as missing,
/// so a tool version that reshapes a field the adapter doesn't need never breaks the hook. Fields
/// the adapters must not forward (prompts, tool input, transcripts) are simply never read.
struct AgentHookPayload {
    private let object: [String: Any]

    init(json data: Data) throws(AgentHookError) {
        guard !data.isEmpty,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .unreadablePayload
        }
        self.object = object
    }

    /// A string field, or nil when it is missing, empty or not a string.
    func string(_ key: String) -> String? {
        guard let value = object[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    /// The string elements of an array field.
    func strings(_ key: String) -> [String] {
        (object[key] as? [Any])?.compactMap { $0 as? String } ?? []
    }
}

/// What one hook invocation reports about its session.
enum AgentHookUpdate: Equatable, Sendable {
    /// The session's new status. `message` and `task` are optional display text.
    case status(DeveloperActivityStatus, message: String? = nil, task: String? = nil)
    /// The session is over; NotchDeck removes it.
    case end
}

/// What every message from one hook invocation shares: who sends it and where the session runs.
///
/// Values that would fail the protocol's validation are dropped rather than failing the message:
/// a session ID with unexpected characters is omitted (the session is then identified by its
/// workspace), and so is a relative or overlong workspace path.
struct AgentHookContext: Equatable, Sendable {
    var provider: String
    var providerName: String
    var session: String?
    var workspace: String?
    var terminal: String?

    init(provider: String, providerName: String, session: String?, workspace: String?, environment: [String: String]) {
        self.provider = provider
        self.providerName = providerName
        self.session = session.flatMap { Self.isValidSession($0) ? $0 : nil }
        self.workspace = workspace.flatMap { Self.isValidWorkspace($0) ? $0 : nil }
        self.terminal = TerminalHint.bundleIdentifier(environment: environment)
    }

    /// The validated message for `update`; empty when there is nothing to send.
    func messages(for update: AgentHookUpdate?) -> [DeveloperBridgeMessage] {
        guard let update else { return [] }
        var message = DeveloperBridgeMessage(
            provider: provider,
            providerName: providerName,
            session: session,
            workspace: workspace,
            terminal: terminal
        )
        switch update {
        case .status(let status, let text, let task):
            message.status = status
            message.message = text
            message.task = task
        case .end:
            message.type = .end
        }
        // Normalizes (sanitizes and truncates text) exactly as NotchDeck will.
        guard let valid = try? message.validated() else { return [] }
        return [valid]
    }

    /// Whether `session` matches the protocol's session ID rule.
    static func isValidSession(_ session: String) -> Bool {
        (try? DeveloperBridgeMessage(provider: "probe", session: session, status: .working).validated()) != nil
    }

    /// Whether `path` is usable as a workspace: absolute, within the length limit, no control
    /// characters.
    static func isValidWorkspace(_ path: String) -> Bool {
        path.hasPrefix("/")
            && path.utf8.count <= DeveloperProtocol.maxPathLength
            && !path.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}

/// Free-text helpers.
enum AgentHookText {
    /// How much of a prompt is examined; the task is a single line anyway.
    private static let maxPromptPrefix = 4096

    /// The first non-empty line of a prompt, trimmed, for the opt-in "prompt as task". Nil when
    /// the prompt starts with markup (`<pasted_content …>`, `<task-notification>`), which marks
    /// pasted or machine-generated text rather than something the user typed. The protocol
    /// truncates the result.
    static func taskLine(fromPrompt prompt: String?) -> String? {
        guard let prompt else { return nil }
        let line = prompt.prefix(maxPromptPrefix)
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line, !line.hasPrefix("<") else { return nil }
        return line
    }
}

/// Describes an agent's tool use by the tool's name only — never its input, which can hold
/// commands, file contents and paths.
enum AgentToolActivity {
    /// Tools that run shell commands. Claude Code: `Bash`, `PowerShell`; Codex reports its shell
    /// and unified-exec tools as `Bash`.
    static let commandTools: Set<String> = ["Bash", "PowerShell"]

    /// Short descriptions of well-known tools, by name.
    static let descriptions: [String: String] = [
        // Claude Code
        "Read": "Reading files",
        "NotebookRead": "Reading files",
        "Edit": "Editing files",
        "MultiEdit": "Editing files",
        "Write": "Editing files",
        "NotebookEdit": "Editing files",
        "Glob": "Searching files",
        "Grep": "Searching files",
        "LS": "Searching files",
        "WebFetch": "Searching the web",
        "WebSearch": "Searching the web",
        "Agent": "Running a subagent",
        "Task": "Running a subagent",  // the Agent tool's name in older Claude Code versions
        "TodoWrite": "Updating the plan",
        "TaskCreate": "Updating the plan",
        "TaskUpdate": "Updating the plan",
        "Skill": "Using a skill",
        // Codex
        "apply_patch": "Editing files",
        "update_plan": "Updating the plan",
        "spawn_agent": "Running a subagent",
        "view_image": "Reading files",
    ]

    /// The update for a tool the agent is about to use: running a command for shell tools,
    /// otherwise working with a short description.
    static func update(forTool name: String?) -> AgentHookUpdate {
        guard let name else { return .status(.working) }
        if commandTools.contains(name) { return .status(.runningCommand) }
        if let description = descriptions[name] { return .status(.working, message: description) }
        return .status(.working, message: "Using \(label(forTool: name))")
    }

    /// A display name for a tool: the server name for MCP tools (`mcp__github__create_issue` →
    /// `github`), the tool name when it is a plain identifier, otherwise "a tool".
    static func label(forTool name: String?) -> String {
        guard let name else { return "a tool" }
        if name.hasPrefix("mcp__") {
            let server = name.dropFirst("mcp__".count).components(separatedBy: "__").first
            return label(forServer: server) ?? "a tool"
        }
        return isPlainIdentifier(name) ? name : "a tool"
    }

    /// An MCP server's name when it is a plain identifier.
    static func label(forServer name: String?) -> String? {
        guard let name, isPlainIdentifier(name) else { return nil }
        return name
    }

    private static let identifierCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")

    private static func isPlainIdentifier(_ value: some StringProtocol) -> Bool {
        !value.isEmpty && value.count <= 40 && value.allSatisfy(identifierCharacters.contains)
    }
}

/// The arguments every adapter understands (after `notchctl hook <name>`). Unknown arguments are
/// ignored, so a newer configuration never breaks an older `notchctl`.
struct AgentHookOptions: Equatable, Sendable {
    /// The argument that turns on `promptAsTask`.
    static let promptAsTaskFlag = "--prompt-as-task"

    /// Use the first line of each prompt as the session's task. Off by default: prompts are
    /// private, and the notch is visible to anyone looking at the screen or watching a share.
    var promptAsTask = false

    init(promptAsTask: Bool = false) {
        self.promptAsTask = promptAsTask
    }

    init(arguments: some Sequence<String>) {
        promptAsTask = arguments.contains(Self.promptAsTaskFlag)
    }
}
