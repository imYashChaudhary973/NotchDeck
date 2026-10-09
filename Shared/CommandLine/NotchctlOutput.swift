import Foundation

/// `notchctl`'s exit statuses (the `sysexits.h` values).
enum NotchctlExitCode: Int32, Sendable {
    case success = 0
    /// The command line is wrong (`EX_USAGE`).
    case usage = 64
    /// The message or JSON is invalid (`EX_DATAERR`).
    case invalidMessage = 65
    /// NotchDeck isn't reachable: not running, Developer agents off, or no answer in time
    /// (`EX_UNAVAILABLE`).
    case unavailable = 69
    /// NotchDeck rejected the message, or something else failed (`EX_SOFTWARE`).
    case failure = 70

    static func forClientError(_ error: DeveloperBridgeClientError) -> NotchctlExitCode {
        switch error {
        case .invalidMessage: .invalidMessage
        case .notRunning, .timedOut, .socketPathTooLong: .unavailable
        case .invalidResponse, .connectionFailed: .failure
        }
    }
}

/// `notchctl --help`.
enum NotchctlHelp {
    static func text(adapterNames: [String]) -> String {
        let adapters = adapterNames.isEmpty ? "(none)" : adapterNames.joined(separator: ", ")
        return """
        notchctl — report developer activity to NotchDeck

        USAGE
          notchctl agent <event> --provider ID [options]
          notchctl send [JSON | -]
          notchctl hook <adapter> [arguments…]
          notchctl ping
          notchctl help | --version

        AGENT EVENTS (event → status)
          start → starting          input → needsInput
          update → --status         permission → needsPermission
          working → working         complete → completed
          command → runningCommand  fail → failed
          waiting → waiting         cancel → cancelled
          end → removes the session

        AGENT OPTIONS
          --provider ID      integration ID, e.g. my-tool (alias --app; required)
          --name NAME        display name, e.g. "My Tool"
          --session ID       the tool's session ID
          --project NAME     project name (default: last component of the workspace)
          --workspace PATH   directory the session works in (default: current directory)
          --task TEXT        what the session is working on
          --message TEXT     short status message
          --progress N       completion from 0 to 1
          --terminal ID      bundle ID of the terminal or editor (default: detected; "" for none)
          --status STATUS    status for `update` (default working): starting, working,
                             runningCommand, waiting, needsInput, needsPermission,
                             completed, failed, cancelled

        SEND
          Sends one protocol message, given as an argument or on standard input:
            {"version":1,"type":"event","provider":"my-tool","status":"needsInput",
             "workspace":"/Users/me/Rove","message":"Approval required"}
          type is event (default), end or ping; provider is required for event and end,
          status for event. Optional: providerName, session, project, task, progress, terminal.

        HOOK
          Translates a tool's hook payload with an adapter and sends the result. Always exits 0,
          never prints to standard output, and does nothing when NotchDeck isn't running.
          Adapters: \(adapters)

        OPTIONS
          -q, --quiet        print no errors
          -h, --help         show this help
              --version      show the version

        EXIT CODES
          0 success   64 usage error   65 invalid message   69 NotchDeck not reachable
          70 rejected by NotchDeck or other failure

        EXAMPLES
          notchctl agent start --provider my-tool --task "Implement tabs"
          notchctl agent permission --provider my-tool --message "Approval required"
          notchctl agent complete --provider my-tool
          echo '{"provider":"my-tool","status":"working"}' | notchctl send
        """
    }
}
