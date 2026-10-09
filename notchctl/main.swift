import Darwin
import Foundation

// notchctl reports developer activity to NotchDeck over its local socket. Parsing, the protocol
// and the socket client live in Shared/ and are unit tested; this target only does I/O.

// A closed standard output or error must never kill the process (it may run as a tool's hook).
signal(SIGPIPE, SIG_IGN)

let runner = NotchctlRunner(
    environment: ProcessInfo.processInfo.environment,
    currentDirectory: FileManager.default.currentDirectoryPath
)
exit(runner.run(arguments: Array(CommandLine.arguments.dropFirst())).rawValue)
