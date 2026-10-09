import Darwin
import Foundation

/// Runs a parsed `notchctl` command: reads input, talks to NotchDeck and reports the outcome.
///
/// Standard output carries only `--help`, `--version` and `ping` results; errors go to standard
/// error unless `--quiet`.
struct NotchctlRunner {
    let environment: [String: String]
    let currentDirectory: String

    /// Hook payloads can embed whole files; bigger ones are skipped.
    static let maxHookInputBytes = 8 * 1024 * 1024
    /// A hook must never hold up the tool that runs it.
    static let hookTimeout: TimeInterval = 1

    private var socketURL: URL {
        DeveloperBridgeLocation.clientSocketURL(environment: environment)
    }

    func run(arguments: [String]) -> NotchctlExitCode {
        let command: NotchctlCommand
        do {
            command = try NotchctlCommand.parse(arguments: arguments, environment: environment, currentDirectory: currentDirectory)
        } catch {
            // Parsing failed, so look for the flag directly.
            let quiet = arguments.contains("-q") || arguments.contains("--quiet")
            report("\(error)\nRun 'notchctl --help' for usage.", quiet: quiet)
            return .usage
        }

        switch command.action {
        case .help:
            print(NotchctlHelp.text(adapterNames: AgentHookAdapters.all.map(\.name)))
            return .success
        case .version:
            print("notchctl \(Self.version) (protocol \(DeveloperProtocol.version))")
            return .success
        case .ping:
            let code = send(DeveloperBridgeMessage(type: .ping), quiet: command.quiet)
            if code == .success {
                print("NotchDeck is listening.")
            }
            return code
        case .agent(let message):
            return send(message, quiet: command.quiet)
        case .send(let input):
            return sendRaw(input, quiet: command.quiet)
        case .hook(let adapter, let arguments):
            runHook(adapterName: adapter, arguments: arguments, quiet: command.quiet)
            return .success
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    // MARK: Sending

    private func send(_ message: DeveloperBridgeMessage, quiet: Bool) -> NotchctlExitCode {
        do {
            let response = try DeveloperBridgeClient.send(message, to: socketURL)
            guard response.ok else {
                report("NotchDeck rejected the message: \(response.error ?? "no reason given")", quiet: quiet)
                return .failure
            }
            return .success
        } catch {
            report(error.description, quiet: quiet)
            return NotchctlExitCode.forClientError(error)
        }
    }

    private func sendRaw(_ input: NotchctlCommand.SendInput, quiet: Bool) -> NotchctlExitCode {
        let data: Data
        switch input {
        case .json(let json):
            data = Data(json.utf8)
        case .standardInput:
            // One byte over the limit is enough for `decode` to reject it as too large.
            data = Self.readStandardInput(limit: DeveloperProtocol.maxMessageBytes, drain: false).data
        }
        do {
            let message = try DeveloperBridgeMessage.decode(data)
            return send(message, quiet: quiet)
        } catch {
            report("Invalid message: \(error)", quiet: quiet)
            return .invalidMessage
        }
    }

    // MARK: Hooks

    /// Never disturbs the calling tool: prints nothing to standard output, at most one line to
    /// standard error, gives up quickly, and stays silent when NotchDeck isn't running.
    private func runHook(adapterName: String?, arguments: [String], quiet: Bool) {
        var warning: String?
        defer {
            if let warning { report(warning, quiet: quiet) }
        }
        guard let adapterName, let adapter = AgentHookAdapters.adapter(named: adapterName) else {
            let name = adapterName.flatMap { DeveloperBridgeMessage.sanitizedText($0, maxLength: 40) }
            warning = name.map { "hook: unknown adapter '\($0)'." } ?? "hook: missing adapter name."
            return
        }

        var standardInput = Data()
        // A terminal isn't a payload: some tools start hooks with the user's terminal as standard
        // input (e.g. Codex before 0.100 for `notify`), and reading it would wait for typing.
        if adapter.readsStandardInput, isatty(STDIN_FILENO) == 0 {
            // Drained to the end even when too large, so the tool never writes into a closed pipe.
            let input = Self.readStandardInput(limit: Self.maxHookInputBytes, drain: true)
            guard !input.exceededLimit else {
                warning = "hook \(adapter.name): payload too large, skipped."
                return
            }
            standardInput = input.data
        }

        let messages: [DeveloperBridgeMessage]
        do {
            messages = try adapter.messages(for: AgentHookInput(standardInput: standardInput, arguments: arguments, environment: environment))
        } catch {
            warning = "hook \(adapter.name): couldn't read the payload."
            return
        }

        for message in messages {
            do {
                let response = try DeveloperBridgeClient.send(message, to: socketURL, timeout: Self.hookTimeout)
                if !response.ok {
                    warning = "hook \(adapter.name): NotchDeck rejected a message."
                }
            } catch .notRunning {
                return
            } catch .invalidMessage {
                warning = "hook \(adapter.name): produced an invalid message."
            } catch {
                // Timed out or failed: later messages would most likely fare no better.
                warning = "hook \(adapter.name): \(error.description)"
                return
            }
        }
    }

    // MARK: I/O

    /// Reads standard input until end of file or until more than `limit` bytes arrived. With
    /// `drain`, bytes past the limit are still read, and discarded.
    private static func readStandardInput(limit: Int, drain: Bool) -> (data: Data, exceededLimit: Bool) {
        var data = Data()
        var exceededLimit = false
        while true {
            guard let chunk = try? FileHandle.standardInput.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            if exceededLimit { continue }
            data.append(chunk)
            if data.count > limit {
                exceededLimit = true
                guard drain else { break }
                data = Data(data.prefix(limit + 1))
            }
        }
        return (data, exceededLimit)
    }

    /// Prints one error to standard error (`fputs`, which unlike `FileHandle.write` can't raise an
    /// exception on a closed pipe).
    private func report(_ message: String, quiet: Bool) {
        guard !quiet else { return }
        fputs("notchctl: \(message)\n", stderr)
    }
}
