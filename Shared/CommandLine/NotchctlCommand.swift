import Foundation

/// What `notchctl` was asked to do.
///
/// Parsing is pure (no I/O), so it is unit tested; `notchctl/` performs the I/O. Messages built here
/// are not yet validated: `DeveloperBridgeMessage.validated()` reports invalid values (exit 65),
/// while this parser only reports command lines it doesn't understand (exit 64).
struct NotchctlCommand: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case help
        case version
        /// Checks that NotchDeck is listening.
        case ping
        /// `agent <event>`: the message to send.
        case agent(DeveloperBridgeMessage)
        /// `send`: a raw protocol message.
        case send(SendInput)
        /// `hook <adapter>`: the adapter name (nil when missing) and the remaining arguments, verbatim.
        case hook(adapter: String?, arguments: [String])
    }

    enum SendInput: Equatable, Sendable {
        case json(String)
        case standardInput
    }

    var action: Action
    /// `--quiet` / `-q`: print no errors.
    var quiet = false
}

/// `notchctl agent <event>`.
enum NotchctlAgentEvent: String, CaseIterable, Sendable {
    case start, update, working, command, waiting, input, permission, complete, fail, cancel, end

    /// The status the event reports. `update` reports `--status` (default `working`); `end` sends
    /// an `end` message, which has no status.
    var status: DeveloperActivityStatus? {
        switch self {
        case .start: .starting
        case .update, .working: .working
        case .command: .runningCommand
        case .waiting: .waiting
        case .input: .needsInput
        case .permission: .needsPermission
        case .complete: .completed
        case .fail: .failed
        case .cancel: .cancelled
        case .end: nil
        }
    }
}

/// A command line `notchctl` doesn't understand (exit 64).
enum NotchctlUsageError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case missingAgentEvent
    case unknownAgentEvent(String)
    case unknownOption(String)
    case missingValue(option: String)
    case invalidValue(option: String, value: String)
    case missingOption(String)
    case unexpectedArgument(String)
    /// `--status` given to an event other than `update`.
    case statusNotAllowed(NotchctlAgentEvent)

    var description: String {
        switch self {
        case .missingCommand: "Missing command."
        case .unknownCommand(let command): "Unknown command '\(Self.quoted(command))'."
        case .missingAgentEvent: "Missing agent event, e.g. 'notchctl agent start'."
        case .unknownAgentEvent(let event): "Unknown agent event '\(Self.quoted(event))'."
        case .unknownOption(let option): "Unknown option '\(Self.quoted(option))'."
        case .missingValue(let option): "Option '\(option)' needs a value."
        case .invalidValue(let option, let value): "Invalid value '\(Self.quoted(value))' for '\(option)'."
        case .missingOption(let option): "Missing required option '\(option)'."
        case .unexpectedArgument(let argument): "Unexpected argument '\(Self.quoted(argument))'."
        case .statusNotAllowed(let event): "'--status' only works with 'agent update', not 'agent \(event.rawValue)'."
        }
    }

    /// The user's own input, made safe to print on one line.
    private static func quoted(_ value: String) -> String {
        DeveloperBridgeMessage.sanitizedText(value, maxLength: 80) ?? ""
    }
}

extension NotchctlCommand {
    /// Parses `notchctl`'s arguments (without the program name).
    /// - Parameters:
    ///   - environment: For the default `--terminal`.
    ///   - currentDirectory: The default `--workspace`, and what a relative one is resolved against.
    static func parse(
        arguments: [String],
        environment: [String: String],
        currentDirectory: String
    ) throws(NotchctlUsageError) -> NotchctlCommand {
        var quiet = false
        var remaining = arguments[...]
        while let first = remaining.first, first.hasPrefix("-") {
            remaining.removeFirst()
            switch first {
            case "-q", "--quiet": quiet = true
            case "-h", "--help": return NotchctlCommand(action: .help, quiet: quiet)
            case "--version": return NotchctlCommand(action: .version, quiet: quiet)
            default: throw .unknownOption(first)
            }
        }
        guard let command = remaining.popFirst() else { throw .missingCommand }
        let rest = Array(remaining)

        let action: Action
        switch command {
        case "help":
            action = .help
        case "version":
            action = .version
        case "ping":
            action = try parsePing(rest, quiet: &quiet)
        case "send":
            action = try parseSend(rest, quiet: &quiet)
        case "hook":
            // Everything after the adapter belongs to it, flags included.
            action = .hook(adapter: rest.first, arguments: Array(rest.dropFirst()))
        case "agent":
            action = try parseAgent(rest, quiet: &quiet, environment: environment, currentDirectory: currentDirectory)
        default:
            throw .unknownCommand(command)
        }
        return NotchctlCommand(action: action, quiet: quiet)
    }

    private static func parsePing(_ arguments: [String], quiet: inout Bool) throws(NotchctlUsageError) -> Action {
        for argument in arguments {
            switch argument {
            case "-q", "--quiet": quiet = true
            case "-h", "--help": return .help
            default: throw argument.hasPrefix("-") ? .unknownOption(argument) : .unexpectedArgument(argument)
            }
        }
        return .ping
    }

    private static func parseSend(_ arguments: [String], quiet: inout Bool) throws(NotchctlUsageError) -> Action {
        var input: SendInput?
        for argument in arguments {
            switch argument {
            case "-q", "--quiet": quiet = true
            case "-h", "--help": return .help
            case "-":
                guard input == nil else { throw .unexpectedArgument(argument) }
                input = .standardInput
            default:
                guard !argument.hasPrefix("-") else { throw .unknownOption(argument) }
                guard input == nil else { throw .unexpectedArgument(argument) }
                input = .json(argument)
            }
        }
        return .send(input ?? .standardInput)
    }

    private enum AgentOption: String {
        case provider = "--provider"
        case app = "--app"
        case name = "--name"
        case session = "--session"
        case project = "--project"
        case workspace = "--workspace"
        case task = "--task"
        case message = "--message"
        case progress = "--progress"
        case terminal = "--terminal"
        case status = "--status"
    }

    private static func parseAgent(
        _ arguments: [String],
        quiet: inout Bool,
        environment: [String: String],
        currentDirectory: String
    ) throws(NotchctlUsageError) -> Action {
        guard let first = arguments.first else { throw .missingAgentEvent }
        if first == "-h" || first == "--help" { return .help }
        guard let event = NotchctlAgentEvent(rawValue: first) else {
            throw first.hasPrefix("-") ? .missingAgentEvent : .unknownAgentEvent(first)
        }

        var values: [AgentOption: String] = [:]
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            switch argument {
            case "-q", "--quiet":
                quiet = true
                continue
            case "-h", "--help":
                return .help
            default:
                break
            }
            guard argument.hasPrefix("--") else { throw .unexpectedArgument(argument) }
            var name = argument
            var value: String?
            if let equals = argument.firstIndex(of: "=") {
                name = String(argument[..<equals])
                value = String(argument[argument.index(after: equals)...])
            }
            guard let option = AgentOption(rawValue: name) else { throw .unknownOption(name) }
            if value == nil {
                // A following option means the value was forgotten; `--message=--x` still works.
                guard index < arguments.count, !arguments[index].hasPrefix("--") else { throw .missingValue(option: name) }
                value = arguments[index]
                index += 1
            }
            values[option == .app ? .provider : option] = value
        }

        guard let provider = values[.provider] else { throw .missingOption("--provider") }

        let workspace = absolutePath(values[.workspace] ?? currentDirectory, relativeTo: currentDirectory)
        let status: DeveloperActivityStatus?
        if let rawStatus = values[.status] {
            guard event == .update else { throw .statusNotAllowed(event) }
            guard let parsed = parseStatus(rawStatus) else { throw .invalidValue(option: "--status", value: rawStatus) }
            status = parsed
        } else {
            status = event.status
        }
        var progress: Double?
        if let rawProgress = values[.progress] {
            guard let value = Double(rawProgress), value.isFinite, (0...1).contains(value) else {
                throw .invalidValue(option: "--progress", value: rawProgress)
            }
            progress = value
        }
        // An empty `--terminal ""` turns detection off.
        let terminal = values[.terminal].map { $0.isEmpty ? nil : $0 } ?? TerminalHint.bundleIdentifier(environment: environment)

        return .agent(DeveloperBridgeMessage(
            type: event == .end ? .end : .event,
            provider: provider,
            providerName: values[.name],
            session: values[.session],
            // No default: NotchDeck shows the workspace folder's name until a project is reported,
            // and a later event without `--project` must not replace one reported earlier.
            project: values[.project],
            workspace: workspace,
            task: values[.task],
            status: status,
            message: values[.message],
            progress: progress,
            terminal: terminal
        ))
    }

    /// Accepts the wire names case-insensitively, with or without `-`/`_` (`running-command`).
    static func parseStatus(_ value: String) -> DeveloperActivityStatus? {
        let key = value.lowercased().filter { $0 != "-" && $0 != "_" }
        return DeveloperActivityStatus.allCases.first { $0.rawValue.lowercased() == key }
    }

    /// `path` made absolute against `directory` and standardized ("." and ".." resolved).
    static func absolutePath(_ path: String, relativeTo directory: String) -> String {
        let absolute = path.hasPrefix("/") ? path : directory + "/" + path
        return (absolute as NSString).standardizingPath
    }
}
