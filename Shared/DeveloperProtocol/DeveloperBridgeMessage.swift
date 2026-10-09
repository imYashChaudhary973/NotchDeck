import Foundation

// Compiled into both NotchDeck and notchctl, so both sides of the bridge share one schema.
// The protocol is documented in docs/developer-activity-protocol.md.

/// Limits and the schema version of the developer activity protocol.
///
/// A coding tool (Claude Code, Codex, a build script…) reports what it is doing as one JSON object
/// per connection, sent by `notchctl` over NotchDeck's local socket. `version` names the schema; a
/// receiver rejects versions it doesn't know and ignores keys it doesn't know.
enum DeveloperProtocol {
    /// The schema version this build speaks.
    static let version = 1
    /// Largest request accepted, in bytes. Anything longer is rejected without being decoded.
    static let maxMessageBytes = 16 * 1024
    /// Largest response a client reads, in bytes.
    static let maxResponseBytes = 4 * 1024

    static let maxProviderLength = 64
    static let maxSessionLength = 128
    static let maxTerminalLength = 155
    static let maxNameLength = 64
    static let maxTextLength = 240
    static let maxPathLength = 1024
}

/// What an agent session is doing. Raw values are the wire format.
enum DeveloperActivityStatus: String, Codable, CaseIterable, Sendable {
    case starting
    case working
    case runningCommand
    case waiting
    case needsInput
    case needsPermission
    case completed
    case failed
    case cancelled

    /// The session's work is over (it may still be shown for a while).
    var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        default: false
        }
    }

    /// The agent can't continue until the user acts.
    var needsAttention: Bool {
        self == .needsInput || self == .needsPermission
    }
}

/// One message from a developer tool to NotchDeck.
///
/// ```json
/// {"version": 1, "type": "event", "provider": "claude-code", "session": "8f1c…",
///  "workspace": "/Users/me/Rove", "status": "needsPermission", "message": "Claude needs your permission to use Bash"}
/// ```
///
/// Only `provider` (for `event` and `end`) and `status` (for `event`) are required; `version`
/// defaults to 1 and `type` to `event`. Use `decode(_:)` for bytes from another process.
struct DeveloperBridgeMessage: Codable, Equatable, Sendable {
    enum MessageType: String, Codable, Sendable {
        /// Creates or updates a session.
        case event
        /// Removes a session at once, e.g. because the tool's session ended.
        case end
        /// Checks that NotchDeck is listening. Changes nothing.
        case ping
    }

    var version: Int
    var type: MessageType
    /// Integration ID, e.g. `claude-code`: lowercase letters, digits, `.`, `_` and `-`.
    var provider: String?
    /// Display name, e.g. `Claude Code`. The app derives one from `provider` when missing.
    var providerName: String?
    /// The tool's own session ID. A session is identified by provider + session; without one, by
    /// provider + workspace, then provider + project (see `sessionKey`).
    var session: String?
    var project: String?
    /// Absolute path of the directory the session works in.
    var workspace: String?
    /// What the session is working on, e.g. "Implement tab management".
    var task: String?
    var status: DeveloperActivityStatus?
    /// A short status message, e.g. "Claude needs your permission to use Bash".
    var message: String?
    /// Completion fraction in `0...1`.
    var progress: Double?
    /// Bundle identifier of the app the session runs in (a terminal or editor), e.g.
    /// `com.apple.Terminal`. Lets NotchDeck bring that app forward.
    var terminal: String?

    init(
        version: Int = DeveloperProtocol.version,
        type: MessageType = .event,
        provider: String? = nil,
        providerName: String? = nil,
        session: String? = nil,
        project: String? = nil,
        workspace: String? = nil,
        task: String? = nil,
        status: DeveloperActivityStatus? = nil,
        message: String? = nil,
        progress: Double? = nil,
        terminal: String? = nil
    ) {
        self.version = version
        self.type = type
        self.provider = provider
        self.providerName = providerName
        self.session = session
        self.project = project
        self.workspace = workspace
        self.task = task
        self.status = status
        self.message = message
        self.progress = progress
        self.terminal = terminal
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        type = try container.decodeIfPresent(MessageType.self, forKey: .type) ?? .event
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
        session = try container.decodeIfPresent(String.self, forKey: .session)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        task = try container.decodeIfPresent(String.self, forKey: .task)
        status = try container.decodeIfPresent(DeveloperActivityStatus.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        terminal = try container.decodeIfPresent(String.self, forKey: .terminal)
    }

    /// Identifies the session the message is about: provider plus session ID, workspace or project.
    /// Nil for messages without a provider (pings).
    var sessionKey: String? {
        guard let provider else { return nil }
        if let session { return "\(provider)|session:\(session)" }
        if let workspace { return "\(provider)|workspace:\(workspace)" }
        if let project { return "\(provider)|project:\(project)" }
        return "\(provider)|default"
    }
}

/// Why a message was rejected. `description` is safe to send back to the client.
enum DeveloperProtocolError: Error, Equatable, Sendable, CustomStringConvertible {
    case tooLarge
    /// Not a JSON object of the expected shape.
    case malformed
    case unsupportedVersion(Int)
    case missingField(String)
    case invalidField(String)

    var description: String {
        switch self {
        case .tooLarge: "Message is larger than \(DeveloperProtocol.maxMessageBytes) bytes."
        case .malformed: "Message is not a valid developer activity JSON object."
        case .unsupportedVersion(let version): "Protocol version \(version) is not supported (this NotchDeck speaks \(DeveloperProtocol.version))."
        case .missingField(let field): "Missing required field '\(field)'."
        case .invalidField(let field): "Invalid value for '\(field)'."
        }
    }
}

extension DeveloperBridgeMessage {
    /// Decodes and validates a message received from another process. The input is untrusted: its
    /// size is bounded, it is decoded structurally, identifiers must match their patterns, and free
    /// text is sanitized and truncated.
    static func decode(_ data: Data) throws(DeveloperProtocolError) -> DeveloperBridgeMessage {
        guard data.count <= DeveloperProtocol.maxMessageBytes else { throw .tooLarge }
        let message: DeveloperBridgeMessage
        do {
            message = try JSONDecoder().decode(DeveloperBridgeMessage.self, from: data)
        } catch {
            throw .malformed
        }
        return try message.validated()
    }

    /// The message as JSON, ready to send.
    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Checks the message and returns it normalized: the provider lowercased, text fields with
    /// control characters replaced and whitespace collapsed (empty ones removed), long text
    /// truncated, and the workspace path standardized.
    func validated() throws(DeveloperProtocolError) -> DeveloperBridgeMessage {
        guard version >= 1 else { throw .invalidField("version") }
        guard version <= DeveloperProtocol.version else { throw .unsupportedVersion(version) }
        if type == .ping {
            return DeveloperBridgeMessage(version: version, type: .ping)
        }

        var result = self
        guard let rawProvider = provider?.trimmingCharacters(in: .whitespaces), !rawProvider.isEmpty else {
            throw .missingField("provider")
        }
        let provider = rawProvider.lowercased()
        guard Self.matches(provider, first: Self.lowercaseAlphanumerics, rest: Self.providerCharacters,
                           maxLength: DeveloperProtocol.maxProviderLength) else {
            throw .invalidField("provider")
        }
        result.provider = provider

        if let session {
            guard Self.matches(session, first: Self.sessionCharacters, rest: Self.sessionCharacters,
                               maxLength: DeveloperProtocol.maxSessionLength) else {
                throw .invalidField("session")
            }
        }
        if let terminal {
            guard Self.isValidBundleIdentifier(terminal) else { throw .invalidField("terminal") }
        }
        if let workspace {
            result.workspace = try Self.validatedPath(workspace)
        }
        if let progress {
            guard progress.isFinite, (0...1).contains(progress) else { throw .invalidField("progress") }
        }

        result.providerName = Self.sanitizedText(providerName, maxLength: DeveloperProtocol.maxNameLength)
        result.project = Self.sanitizedText(project, maxLength: DeveloperProtocol.maxNameLength)
        result.task = Self.sanitizedText(task, maxLength: DeveloperProtocol.maxTextLength)
        result.message = Self.sanitizedText(message, maxLength: DeveloperProtocol.maxTextLength)

        switch type {
        case .event:
            guard status != nil else { throw .missingField("status") }
        case .end:
            result.status = nil
            result.progress = nil
        case .ping:
            break
        }
        return result
    }

    // MARK: Validation helpers

    private static let lowercaseAlphanumerics = Set("abcdefghijklmnopqrstuvwxyz0123456789")
    private static let alphanumerics = lowercaseAlphanumerics.union("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let providerCharacters = lowercaseAlphanumerics.union("._-")
    private static let sessionCharacters = alphanumerics.union("._:@+=/-")
    private static let bundleIdentifierCharacters = alphanumerics.union(".-")

    /// Whether `value` has the shape of a bundle identifier (the `terminal` field's rule).
    static func isValidBundleIdentifier(_ value: String) -> Bool {
        matches(value, first: alphanumerics, rest: bundleIdentifierCharacters, maxLength: DeveloperProtocol.maxTerminalLength)
    }

    private static func matches(_ value: String, first: Set<Character>, rest: Set<Character>, maxLength: Int) -> Bool {
        guard let head = value.first, value.count <= maxLength, first.contains(head) else { return false }
        return value.dropFirst().allSatisfy(rest.contains)
    }

    private static func validatedPath(_ path: String) throws(DeveloperProtocolError) -> String {
        guard path.hasPrefix("/"),
              path.utf8.count <= DeveloperProtocol.maxPathLength,
              !path.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw .invalidField("workspace")
        }
        // Resolves "." and ".." lexically; never touches the file system.
        return (path as NSString).standardizingPath
    }

    /// Replaces control and invisible formatting characters (including bidirectional overrides)
    /// with spaces, collapses whitespace and truncates. Returns nil when nothing is left.
    static func sanitizedText(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in value.unicodeScalars {
            let category = scalar.properties.generalCategory
            let isInvisible = (category == .control || category == .format || category == .lineSeparator
                || category == .paragraphSeparator) && scalar != "\u{200D}"  // keep emoji joiners
            if isInvisible || scalar.properties.isWhitespace {
                pendingSpace = !scalars.isEmpty
                continue
            }
            if pendingSpace {
                scalars.append(" ")
                pendingSpace = false
            }
            scalars.append(scalar)
        }
        let text = String(scalars)
        guard !text.isEmpty else { return nil }
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength - 1)) + "…"
    }
}

/// NotchDeck's reply to a message: one JSON object.
struct DeveloperBridgeResponse: Codable, Equatable, Sendable {
    var ok: Bool
    /// The protocol version the app speaks.
    var version: Int
    /// Why the message was rejected, when `ok` is false.
    var error: String?

    static let success = DeveloperBridgeResponse(ok: true, version: DeveloperProtocol.version, error: nil)

    static func failure(_ error: DeveloperProtocolError) -> DeveloperBridgeResponse {
        DeveloperBridgeResponse(ok: false, version: DeveloperProtocol.version, error: error.description)
    }
}
