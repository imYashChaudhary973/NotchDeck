import Foundation
@testable import NotchDeck

/// A hook input with `json` on standard input.
func hookInput(_ json: String, arguments: [String] = [], environment: [String: String] = [:]) -> AgentHookInput {
    AgentHookInput(standardInput: Data(json.utf8), arguments: arguments, environment: environment)
}

extension DeveloperBridgeMessage {
    /// Every text field, for checking that private content never leaks into a message.
    var allText: [String] {
        [provider, providerName, session, project, workspace, task, message, terminal].compactMap { $0 }
    }

    /// Whether the message is unchanged by validation, i.e. it is exactly what NotchDeck accepts.
    var isValidated: Bool {
        (try? validated()) == self
    }
}
