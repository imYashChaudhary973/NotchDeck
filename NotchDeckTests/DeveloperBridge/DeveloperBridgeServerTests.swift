import Darwin
import Foundation
import Testing
@testable import NotchDeck

/// A socket path in a fresh directory under /tmp: short, because `sun_path` holds only 103 bytes.
/// The directory itself is created by the server unless a test makes it first.
private struct TemporarySocket {
    let directory: URL
    let url: URL

    init() {
        directory = URL(filePath: "/tmp/nd-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        url = directory.appending(path: "b.sock", directoryHint: .notDirectory)
    }

    var path: String { UnixSocket.path(of: url) }
    var directoryPath: String { (path as NSString).deletingLastPathComponent }

    func createDirectory(mode: mode_t = 0o700) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        chmod(directoryPath, mode)
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: directoryPath)
    }
}

/// Collects delivered messages.
@MainActor
private final class MessageRecorder {
    private(set) var messages: [DeveloperBridgeMessage] = []
    private(set) var deliveredOnMainThread = true

    func record(_ message: DeveloperBridgeMessage) {
        deliveredOnMainThread = deliveredOnMainThread && Thread.isMainThread
        messages.append(message)
    }

    /// Waits, at most `timeout`, until `count` messages arrived.
    func waitForMessages(_ count: Int, timeout: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while messages.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return messages.count >= count
    }
}

/// Runs blocking socket work off the main actor, so the server's deliveries can proceed.
private func offMain<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
    await Task.detached(operation: body).value
}

private func send(_ message: DeveloperBridgeMessage, to url: URL) async -> Result<DeveloperBridgeResponse, DeveloperBridgeClientError> {
    await offMain { Result { () throws(DeveloperBridgeClientError) in try DeveloperBridgeClient.send(message, to: url, timeout: 3) } }
}

private func exchange(_ payload: String, with url: URL) async -> Result<DeveloperBridgeResponse, DeveloperBridgeClientError> {
    await offMain { Result { () throws(DeveloperBridgeClientError) in try DeveloperBridgeClient.exchange(Data(payload.utf8), with: url, timeout: 3) } }
}

/// A raw client connection, for tests that misbehave on purpose.
private func connectRaw(to path: String) throws -> Int32 {
    let descriptor = try UnixSocket.makeStreamSocket()
    do {
        try UnixSocket.connect(descriptor, to: try #require(UnixSocket.address(forPath: path)), deadline: UnixSocket.deadline(after: 2))
    } catch {
        close(descriptor)
        throw error
    }
    return descriptor
}

/// Reads one frame from a raw connection, off the main actor.
private func readFrame(from descriptor: Int32, timeout: TimeInterval = 3) async -> DeveloperBridgeFraming.Frame? {
    await offMain { try? UnixSocket.readFrame(from: descriptor, limit: DeveloperProtocol.maxResponseBytes, deadline: UnixSocket.deadline(after: timeout)) }
}

/// Leaves a socket file nobody listens on, like a crashed NotchDeck does.
private func makeStaleSocket(at path: String) throws {
    let descriptor = try UnixSocket.makeStreamSocket()
    defer { close(descriptor) }
    let address = try #require(UnixSocket.address(forPath: path))
    let result = UnixSocket.withSockaddr(address) { bind(descriptor, $0, $1) }
    try #require(result == 0)
}

private func fileMode(_ path: String) -> mode_t? {
    var info = stat()
    return lstat(path, &info) == 0 ? info.st_mode : nil
}

private let validEvent = DeveloperBridgeMessage(provider: "my-tool", session: "s1", status: .working)

@MainActor
struct DeveloperBridgeServerTests {
    // MARK: Delivery

    @Test func deliversValidatedEventsOnTheMainActor() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        let recorder = MessageRecorder()
        try server.start { recorder.record($0) }
        defer { server.stop() }

        let json = #"{"provider":"Claude-Code","status":"needsPermission","workspace":"/Users/me/x/../Rove","message":"Needs\nyou‮"}"#
        let response = try await exchange(json, with: socket.url).get()

        #expect(response == .success)
        #expect(await recorder.waitForMessages(1))
        #expect(recorder.messages == [DeveloperBridgeMessage(provider: "claude-code", workspace: "/Users/me/Rove", status: .needsPermission, message: "Needs you")])
        #expect(recorder.deliveredOnMainThread)
    }

    @Test func deliversEndMessagesAndKeepsArrivalOrder() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        let recorder = MessageRecorder()
        try server.start { recorder.record($0) }
        defer { server.stop() }

        let messages = (1...4).map { DeveloperBridgeMessage(provider: "my-tool", session: "s\($0)", status: .working) }
            + [DeveloperBridgeMessage(type: .end, provider: "my-tool", session: "s1")]
        for message in messages {
            #expect(try await send(message, to: socket.url).get() == .success)
        }
        #expect(await recorder.waitForMessages(messages.count))
        #expect(recorder.messages == messages)
    }

    @Test func answersPingsWithoutDeliveringThem() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        let recorder = MessageRecorder()
        try server.start { recorder.record($0) }
        defer { server.stop() }

        #expect(try await send(DeveloperBridgeMessage(type: .ping), to: socket.url).get() == .success)
        // Deliveries keep their order, so once the event is in, the ping would have been too.
        #expect(try await send(validEvent, to: socket.url).get() == .success)
        #expect(await recorder.waitForMessages(1))
        #expect(recorder.messages == [validEvent])
    }

    @Test func rejectsMalformedAndInvalidMessagesWithoutDeliveringThem() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        let recorder = MessageRecorder()
        try server.start { recorder.record($0) }
        defer { server.stop() }

        #expect(try await exchange("{not json", with: socket.url).get() == .failure(.malformed))
        #expect(try await exchange("[1,2,3]", with: socket.url).get() == .failure(.malformed))
        #expect(try await exchange("", with: socket.url).get() == .failure(.malformed))
        #expect(try await exchange(#"{"provider":"bad name","status":"working"}"#, with: socket.url).get() == .failure(.invalidField("provider")))
        #expect(try await exchange(#"{"provider":"x"}"#, with: socket.url).get() == .failure(.missingField("status")))
        #expect(try await exchange(#"{"version":9,"type":"ping"}"#, with: socket.url).get() == .failure(.unsupportedVersion(9)))

        #expect(try await send(validEvent, to: socket.url).get() == .success)
        #expect(await recorder.waitForMessages(1))
        #expect(recorder.messages == [validEvent])
    }

    @Test func rejectsOversizedRequests() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        let recorder = MessageRecorder()
        try server.start { recorder.record($0) }
        defer { server.stop() }

        let padding = String(repeating: "a", count: 20_000)
        #expect(try await exchange(#"{"provider":"x","status":"working","message":"\#(padding)"}"#, with: socket.url).get() == .failure(.tooLarge))

        let json = #"{"provider":"x","status":"working"}"#
        let padded = json + String(repeating: " ", count: DeveloperProtocol.maxMessageBytes - json.utf8.count)
        #expect(try await exchange(padded, with: socket.url).get() == .success)
        #expect(await recorder.waitForMessages(1))
        #expect(recorder.messages.map(\.provider) == ["x"])
    }

    @Test func acceptsARequestEndedByClosingTheWriteSide() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        let recorder = MessageRecorder()
        try server.start { recorder.record($0) }
        defer { server.stop() }

        let descriptor = try connectRaw(to: socket.path)
        defer { close(descriptor) }
        try UnixSocket.write(Data(#"{"provider":"eof","status":"completed"}"#.utf8), to: descriptor, deadline: UnixSocket.deadline(after: 2))
        shutdown(descriptor, SHUT_WR)

        guard case .message(let data) = await readFrame(from: descriptor) else {
            Issue.record("No answer")
            return
        }
        #expect(try JSONDecoder().decode(DeveloperBridgeResponse.self, from: data) == .success)
        #expect(await recorder.waitForMessages(1))
        #expect(recorder.messages.map(\.provider) == ["eof"])
    }

    @Test func answersAnIncompleteRequestWhenItsTimeRunsOut() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url, limits: .init(readTimeout: 0.2))
        let recorder = MessageRecorder()
        try server.start { recorder.record($0) }
        defer { server.stop() }

        let descriptor = try connectRaw(to: socket.path)
        defer { close(descriptor) }
        try UnixSocket.write(Data(#"{"provider":"slow","status":"#.utf8), to: descriptor, deadline: UnixSocket.deadline(after: 2))

        guard case .message(let data) = await readFrame(from: descriptor) else {
            Issue.record("No answer")
            return
        }
        #expect(try JSONDecoder().decode(DeveloperBridgeResponse.self, from: data) == .failure(.malformed))
        #expect(recorder.messages.isEmpty)
    }

    @Test func closesConnectionsOverTheLimitAtOnce() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url, limits: .init(readTimeout: 10, maxConnections: 2))
        try server.start { _ in }
        defer { server.stop() }

        let first = try connectRaw(to: socket.path)
        let second = try connectRaw(to: socket.path)
        let third = try connectRaw(to: socket.path)
        defer { close(third) }

        // Closed unanswered, long before the read timeout.
        let started = ContinuousClock.now
        #expect(await readFrame(from: third) == .message(Data()))
        #expect(ContinuousClock.now - started < .seconds(5))

        // Freed slots are usable again (once the server has seen the closes, so retry briefly).
        close(first)
        close(second)
        var response: Result<DeveloperBridgeResponse, DeveloperBridgeClientError>
        let deadline = ContinuousClock.now + .seconds(3)
        repeat {
            response = await send(DeveloperBridgeMessage(type: .ping), to: socket.url)
        } while response != .success(.success) && ContinuousClock.now < deadline
        #expect(response == .success(.success))
    }

    // MARK: Socket file and directory

    @Test func createsAPrivateSocketInAPrivateDirectory() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        try socket.createDirectory(mode: 0o755)
        let server = DeveloperBridgeServer(socketURL: socket.url)
        try server.start { _ in }
        defer { server.stop() }

        let socketMode = try #require(fileMode(socket.path))
        #expect(socketMode & S_IFMT == S_IFSOCK)
        #expect(socketMode & 0o777 == 0o600)
        let directoryMode = try #require(fileMode(socket.directoryPath))
        #expect(directoryMode & S_IFMT == S_IFDIR)
        #expect(directoryMode & 0o777 == 0o700)
    }

    @Test func refusesToStartTwiceOnTheSameSocket() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        try server.start { _ in }
        defer { server.stop() }

        let second = DeveloperBridgeServer(socketURL: socket.url)
        #expect(throws: DeveloperBridgeServerError.alreadyRunning) { try second.start { _ in } }
        #expect(!second.isListening)
        // The first server is unaffected.
        #expect(try await send(DeveloperBridgeMessage(type: .ping), to: socket.url).get() == .success)
    }

    @Test func startingAgainWhileListeningReplacesTheHandler() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        let first = MessageRecorder()
        let second = MessageRecorder()
        try server.start { first.record($0) }
        try server.start { second.record($0) }
        defer { server.stop() }

        #expect(try await send(validEvent, to: socket.url).get() == .success)
        #expect(await second.waitForMessages(1))
        #expect(first.messages.isEmpty)
    }

    @Test func replacesAStaleSocket() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        try socket.createDirectory()
        try makeStaleSocket(at: socket.path)
        #expect(await send(DeveloperBridgeMessage(type: .ping), to: socket.url) == .failure(.notRunning))

        let server = DeveloperBridgeServer(socketURL: socket.url)
        try server.start { _ in }
        defer { server.stop() }
        #expect(try await send(DeveloperBridgeMessage(type: .ping), to: socket.url).get() == .success)
    }

    @Test func leavesAFileThatIsNotASocketAlone() throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        try socket.createDirectory()
        try Data("keep".utf8).write(to: socket.url)

        let server = DeveloperBridgeServer(socketURL: socket.url)
        #expect(throws: DeveloperBridgeServerError.socketPathOccupied) { try server.start { _ in } }
        #expect(try Data(contentsOf: socket.url) == Data("keep".utf8))
    }

    @Test func leavesASymlinkAtTheSocketPathAlone() throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        try socket.createDirectory()
        try FileManager.default.createSymbolicLink(atPath: socket.path, withDestinationPath: "/tmp")

        let server = DeveloperBridgeServer(socketURL: socket.url)
        #expect(throws: DeveloperBridgeServerError.socketPathOccupied) { try server.start { _ in } }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: socket.path) == "/tmp")
    }

    @Test func refusesASymlinkedOrNonDirectoryParent() throws {
        let socket = TemporarySocket()
        let target = TemporarySocket()
        defer {
            socket.remove()
            target.remove()
        }
        try target.createDirectory()
        try FileManager.default.createSymbolicLink(atPath: socket.directoryPath, withDestinationPath: target.directoryPath)
        #expect(throws: DeveloperBridgeServerError.unsafeDirectory) { try DeveloperBridgeServer(socketURL: socket.url).start { _ in } }
        #expect(fileMode(target.path) == nil)

        let file = TemporarySocket()
        defer { file.remove() }
        #expect(FileManager.default.createFile(atPath: file.directoryPath, contents: Data()))
        #expect(throws: DeveloperBridgeServerError.unsafeDirectory) { try DeveloperBridgeServer(socketURL: file.url).start { _ in } }
    }

    @Test func refusesASocketPathThatIsTooLong() {
        let long = URL(filePath: "/tmp/" + String(repeating: "d", count: 100) + "/b.sock")
        #expect(throws: DeveloperBridgeServerError.socketPathTooLong) { try DeveloperBridgeServer(socketURL: long).start { _ in } }
        #expect(throws: DeveloperBridgeClientError.socketPathTooLong) {
            try DeveloperBridgeClient.send(DeveloperBridgeMessage(type: .ping), to: long, timeout: 1)
        }
    }

    // MARK: Lifecycle

    @Test func stopRemovesTheSocketAndStartWorksAgain() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        let recorder = MessageRecorder()
        try server.start { recorder.record($0) }

        server.stop()
        server.stop()
        #expect(!server.isListening)
        #expect(fileMode(socket.path) == nil)
        #expect(fileMode(socket.directoryPath) != nil)
        #expect(await send(validEvent, to: socket.url) == .failure(.notRunning))

        try server.start { recorder.record($0) }
        defer { server.stop() }
        #expect(server.isListening)
        #expect(try await send(validEvent, to: socket.url).get() == .success)
        #expect(await recorder.waitForMessages(1))
    }

    @Test func stopLeavesAReplacedSocketPathAlone() throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        try server.start { _ in }
        unlink(socket.path)
        try Data("other".utf8).write(to: socket.url)

        server.stop()
        #expect(try Data(contentsOf: socket.url) == Data("other".utf8))
    }

    @Test func releasingARunningServerRemovesTheSocket() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        do {
            let server = DeveloperBridgeServer(socketURL: socket.url)
            try server.start { _ in }
            #expect(fileMode(socket.path) != nil)
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while fileMode(socket.path) != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(fileMode(socket.path) == nil)
    }

    // MARK: Client and peers

    @Test func clientReportsNotRunningWhenNothingListens() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        #expect(await send(validEvent, to: socket.url) == .failure(.notRunning))
        try socket.createDirectory()
        #expect(await send(validEvent, to: socket.url) == .failure(.notRunning))
    }

    @Test func clientValidatesBeforeConnecting() async {
        let socket = TemporarySocket()
        let invalid = DeveloperBridgeMessage(provider: "my tool", status: .working)
        #expect(await send(invalid, to: socket.url) == .failure(.invalidMessage(.invalidField("provider"))))
    }

    @Test func onlyPeersOfTheSameUserAreAllowed() {
        let me = getuid()
        #expect(DeveloperBridgeServer.allowsPeer(uid: me))
        #expect(DeveloperBridgeServer.allowsPeer(uid: 501, ownUID: 501))
        #expect(!DeveloperBridgeServer.allowsPeer(uid: 502, ownUID: 501))
        #expect(!DeveloperBridgeServer.allowsPeer(uid: 0, ownUID: 501))
        #expect(!DeveloperBridgeServer.allowsPeer(uid: nil, ownUID: 501))
        #expect(!DeveloperBridgeServer.allowsPeer(uid: me &+ 1))
    }
}

// MARK: - notchctl end to end

private struct NotchctlOutput: Sendable {
    var status: Int32
    var standardOutput: String
    var standardError: String
}

/// Runs the `notchctl` embedded in the test host (`NotchDeck.app/Contents/MacOS/notchctl`) with a
/// minimal environment pointing it at `socket`.
private func runNotchctl(
    _ arguments: [String],
    socket: TemporarySocket,
    input: String? = nil,
    currentDirectory: String = "/tmp"
) async throws -> NotchctlOutput {
    let executable = Bundle.main.bundleURL.appending(path: "Contents/MacOS/notchctl")
    try #require(FileManager.default.isExecutableFile(atPath: executable.path(percentEncoded: false)))
    let socketPath = socket.path
    let output = await offMain { () -> NotchctlOutput? in
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ["NOTCHDECK_SOCKET": socketPath, "TERM_PROGRAM": "Apple_Terminal"]
        process.currentDirectoryURL = URL(filePath: currentDirectory, directoryHint: .isDirectory)
        let standardOutput = Pipe()
        let standardError = Pipe()
        let standardInput = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.standardInput = standardInput
        guard (try? process.run()) != nil else { return nil }
        if let input {
            try? standardInput.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        }
        try? standardInput.fileHandleForWriting.close()
        process.waitUntilExit()
        let out = (try? standardOutput.fileHandleForReading.readToEnd()) ?? Data()
        let error = (try? standardError.fileHandleForReading.readToEnd()) ?? Data()
        return NotchctlOutput(status: process.terminationStatus,
                              standardOutput: String(decoding: out, as: UTF8.self),
                              standardError: String(decoding: error, as: UTF8.self))
    }
    return try #require(output)
}

@MainActor
struct NotchctlEndToEndTests {
    @Test func agentEventsReachTheServerSilently() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        let recorder = MessageRecorder()
        try server.start { recorder.record($0) }
        defer { server.stop() }

        let result = try await runNotchctl(["agent", "start", "--provider", "My-Tool", "--task", "Implement\ntabs", "--session", "s1"],
                                           socket: socket, currentDirectory: socket.directoryPath)
        #expect(result.status == 0)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.isEmpty)
        #expect(await recorder.waitForMessages(1))
        let message = try #require(recorder.messages.first)
        let directoryName = socket.directory.lastPathComponent
        #expect(message.provider == "my-tool")
        #expect(message.status == .starting)
        #expect(message.task == "Implement tabs")
        #expect(message.session == "s1")
        #expect(message.project == nil)  // NotchDeck shows the workspace folder's name.
        #expect(message.workspace?.hasSuffix("/" + directoryName) == true)
        #expect(message.terminal == "com.apple.Terminal")
    }

    @Test func sendAndPingWork() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }
        let server = DeveloperBridgeServer(socketURL: socket.url)
        let recorder = MessageRecorder()
        try server.start { recorder.record($0) }
        defer { server.stop() }

        let ping = try await runNotchctl(["ping"], socket: socket)
        #expect(ping.status == 0)
        #expect(ping.standardOutput == "NotchDeck is listening.\n")

        let fromInput = try await runNotchctl(["send"], socket: socket, input: #"{"provider":"stdin","status":"waiting"}"# + "\n")
        #expect(fromInput.status == 0)
        let inline = try await runNotchctl(["send", #"{"type":"end","provider":"inline"}"#], socket: socket)
        #expect(inline.status == 0)
        #expect(fromInput.standardOutput.isEmpty && inline.standardOutput.isEmpty)

        #expect(await recorder.waitForMessages(2))
        #expect(recorder.messages == [DeveloperBridgeMessage(provider: "stdin", status: .waiting),
                                      DeveloperBridgeMessage(type: .end, provider: "inline")])
    }

    @Test func exitCodesDistinguishFailures() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }

        let notRunning = try await runNotchctl(["ping"], socket: socket)
        #expect(notRunning.status == 69)
        #expect(notRunning.standardOutput.isEmpty)
        #expect(!notRunning.standardError.isEmpty)

        let quiet = try await runNotchctl(["-q", "agent", "working", "--provider", "x"], socket: socket)
        #expect(quiet.status == 69)
        #expect(quiet.standardError.isEmpty)

        #expect(try await runNotchctl(["agent", "start"], socket: socket).status == 64)
        #expect(try await runNotchctl(["agent", "start", "--provider", "x", "--bogus", "1"], socket: socket).status == 64)
        #expect(try await runNotchctl([], socket: socket).status == 64)
        #expect(try await runNotchctl(["agent", "start", "--provider", "Bad Name"], socket: socket).status == 65)
        #expect(try await runNotchctl(["send", "[1]"], socket: socket).status == 65)
        #expect(try await runNotchctl(["send"], socket: socket, input: String(repeating: " ", count: 20_000)).status == 65)
    }

    @Test func hooksNeverDisturbTheCallingTool() async throws {
        let socket = TemporarySocket()
        defer { socket.remove() }

        let unknown = try await runNotchctl(["hook", "no-such-tool", "--flag"], socket: socket, input: "{}")
        #expect(unknown.status == 0)
        #expect(unknown.standardOutput.isEmpty)
        #expect(unknown.standardError.split(separator: "\n").count == 1)

        let quiet = try await runNotchctl(["-q", "hook", "no-such-tool"], socket: socket)
        #expect(quiet.status == 0)
        #expect(quiet.standardOutput.isEmpty && quiet.standardError.isEmpty)

        let missing = try await runNotchctl(["hook"], socket: socket)
        #expect(missing.status == 0)
        #expect(missing.standardOutput.isEmpty)
    }

    @Test func printsHelpAndVersion() async throws {
        let socket = TemporarySocket()
        let help = try await runNotchctl(["--help"], socket: socket)
        #expect(help.status == 0)
        #expect(help.standardOutput.contains("USAGE"))
        #expect(help.standardError.isEmpty)
        let version = try await runNotchctl(["--version"], socket: socket)
        #expect(version.status == 0)
        #expect(version.standardOutput.hasPrefix("notchctl "))
        #expect(version.standardOutput.contains("protocol \(DeveloperProtocol.version)"))
    }
}
