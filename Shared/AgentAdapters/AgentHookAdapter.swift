import Foundation

/// What a hook invocation hands an adapter.
struct AgentHookInput: Sendable {
    /// The tool's standard input; empty for adapters that don't read it.
    var standardInput: Data
    /// Arguments after `notchctl hook <name>`.
    var arguments: [String]
    /// The process environment, e.g. for `TerminalHint`.
    var environment: [String: String]

    init(standardInput: Data = Data(), arguments: [String] = [], environment: [String: String] = [:]) {
        self.standardInput = standardInput
        self.arguments = arguments
        self.environment = environment
    }
}

/// Translates a coding tool's own hook or notification payload into generic developer activity
/// messages.
///
/// Adapters run inside `notchctl` (`notchctl hook <name>`), so NotchDeck itself only ever sees the
/// generic protocol and knows nothing about any particular tool. They are pure — no I/O — which
/// keeps them unit testable. Behavior that differs between tool versions stays inside the adapter.
protocol AgentHookAdapter: Sendable {
    /// The name used on the command line, e.g. `claude-code`.
    var name: String { get }
    /// Whether the tool passes its payload on standard input (otherwise in `arguments`).
    var readsStandardInput: Bool { get }
    /// The messages to send, in order. Empty when the payload is irrelevant, such as an unknown
    /// hook event, so new tool versions never break the user's session.
    func messages(for input: AgentHookInput) throws -> [DeveloperBridgeMessage]
}

/// The adapters `notchctl hook` knows.
enum AgentHookAdapters {
    static let all: [any AgentHookAdapter] = [
        ClaudeCodeHookAdapter(),
        CodexHookAdapter(),
        CodexNotifyAdapter(),
    ]

    static func adapter(named name: String) -> (any AgentHookAdapter)? {
        let name = name.lowercased()
        return all.first { $0.name == name }
    }
}
