import Darwin
import Foundation

/// The bridge's socket work, off the main actor.
///
/// `init` prepares the directory and binds the socket synchronously, so `DeveloperBridgeServer`
/// can report failures. After that every mutable property is read and written only on `queue`
/// (dispatch source handlers target it; `resume()` and `shutDown()` hop onto it), which is why the
/// class can be `@unchecked Sendable`. `deinit` has exclusive access by definition.
final class DeveloperBridgeListener: @unchecked Sendable {
    /// One client connection. Confined to `queue`.
    private final class Connection {
        let descriptor: Int32
        let readSource: DispatchSourceRead
        let deadline: DispatchSourceTimer
        var buffer = Data()

        init(descriptor: Int32, readSource: DispatchSourceRead, deadline: DispatchSourceTimer) {
            self.descriptor = descriptor
            self.readSource = readSource
            self.deadline = deadline
        }
    }

    /// Identifies the socket file this listener created, so it never removes someone else's.
    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private let socketPath: String
    private let limits: DeveloperBridgeServer.Limits
    private let deliver: @Sendable (DeveloperBridgeMessage) -> Void
    private let queue = DispatchQueue(label: "com.imyashchaudhary.NotchDeck.DeveloperBridge")
    private let listeningDescriptor: Int32
    private let socketIdentity: FileIdentity

    private var acceptSource: DispatchSourceRead?
    private var isAcceptSuspended = false
    private var connections: [UInt64: Connection] = [:]
    private var lastConnectionID: UInt64 = 0
    private var isShutDown = false

    /// How long accepting pauses after the process ran out of descriptors (the pending connection
    /// would otherwise wake the source again at once).
    private static let acceptRetryDelay: DispatchTimeInterval = .seconds(1)
    /// How long to wait for an answer when probing whether an existing socket is alive.
    private static let probeTimeout: TimeInterval = 0.5

    /// Binds the socket and starts listening; connections are accepted once `resume()` is called.
    /// - Parameter deliver: Called on the listener's queue with each valid `event` or `end` message.
    init(
        socketURL: URL,
        limits: DeveloperBridgeServer.Limits,
        deliver: @escaping @Sendable (DeveloperBridgeMessage) -> Void
    ) throws(DeveloperBridgeServerError) {
        let path = UnixSocket.path(of: socketURL)
        guard let address = UnixSocket.address(forPath: path) else { throw .socketPathTooLong }
        // Derived from the string: a URL's directory path ends in "/", which would make lstat follow a symlink.
        try Self.prepareDirectory((path as NSString).deletingLastPathComponent)
        try Self.removeStaleSocket(at: path, address: address)
        let (descriptor, identity) = try Self.bindAndListen(at: path, address: address, backlog: limits.backlog)

        self.socketPath = path
        self.limits = limits
        self.deliver = deliver
        self.listeningDescriptor = descriptor
        self.socketIdentity = identity
    }

    deinit {
        // Normally `shutDown()` already ran; this covers a listener that was simply released.
        guard !isShutDown else { return }
        cancelSources()
        removeSocketFile()
        if acceptSource == nil {
            close(listeningDescriptor)
        }
    }

    /// Starts accepting connections.
    func resume() {
        queue.async { [self] in
            guard !isShutDown, acceptSource == nil else { return }
            let source = DispatchSource.makeReadSource(fileDescriptor: listeningDescriptor, queue: queue)
            let descriptor = listeningDescriptor
            source.setEventHandler { [weak self] in self?.acceptPendingConnections() }
            source.setCancelHandler { close(descriptor) }
            acceptSource = source
            source.resume()
        }
    }

    /// Closes every connection and the listening socket, and removes the socket file if it is
    /// still the one this listener created. Returns once that is done.
    func shutDown() {
        queue.sync {
            guard !isShutDown else { return }
            isShutDown = true
            cancelSources()
            if acceptSource == nil {
                close(listeningDescriptor)
            }
            removeSocketFile()
        }
    }

    // MARK: Setup

    /// Creates the directory with mode 0700 if needed. An existing one must be a real directory
    /// (not a symlink) owned by the user; its mode is reset to 0700.
    private static func prepareDirectory(_ path: String) throws(DeveloperBridgeServerError) {
        var info = stat()
        if lstat(path, &info) != 0 {
            guard errno == ENOENT else { throw .systemError(operation: "lstat", code: errno) }
            // Parents keep their usual permissions; only the bridge directory itself is private.
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                     withIntermediateDirectories: true)
            guard mkdir(path, 0o700) == 0 || errno == EEXIST else { throw .systemError(operation: "mkdir", code: errno) }
            guard lstat(path, &info) == 0 else { throw .systemError(operation: "lstat", code: errno) }
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else { throw .unsafeDirectory }
        if info.st_mode & 0o777 != 0o700 {
            guard chmod(path, 0o700) == 0 else { throw .systemError(operation: "chmod", code: errno) }
        }
    }

    /// Removes a socket left behind by a NotchDeck that didn't shut down cleanly. A socket that
    /// still answers belongs to a running NotchDeck; anything that isn't a socket is never touched.
    private static func removeStaleSocket(at path: String, address: sockaddr_un) throws(DeveloperBridgeServerError) {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            guard errno == ENOENT else { throw .systemError(operation: "lstat", code: errno) }
            return
        }
        guard info.st_mode & S_IFMT == S_IFSOCK else { throw .socketPathOccupied }
        guard !UnixSocket.isListening(at: address, timeout: probeTimeout) else { throw .alreadyRunning }
        guard unlink(path) == 0 || errno == ENOENT else { throw .systemError(operation: "unlink", code: errno) }
    }

    private static func bindAndListen(
        at path: String,
        address: sockaddr_un,
        backlog: Int32
    ) throws(DeveloperBridgeServerError) -> (Int32, FileIdentity) {
        let descriptor: Int32
        do {
            descriptor = try UnixSocket.makeStreamSocket()
        } catch {
            throw serverError(for: error)
        }
        var isBound = false
        func failure(_ error: DeveloperBridgeServerError) -> DeveloperBridgeServerError {
            close(descriptor)
            if isBound { unlink(path) }
            return error
        }

        let (result, code) = UnixSocket.withSockaddr(address) { (bind(descriptor, $0, $1), errno) }
        guard result == 0 else {
            throw failure(code == EADDRINUSE ? .alreadyRunning : .systemError(operation: "bind", code: code))
        }
        isBound = true
        // The directory already keeps other users out; the socket's own mode is a second barrier.
        guard chmod(path, 0o600) == 0 else { throw failure(.systemError(operation: "chmod", code: errno)) }
        var info = stat()
        guard lstat(path, &info) == 0 else { throw failure(.systemError(operation: "lstat", code: errno)) }
        guard listen(descriptor, backlog) == 0 else { throw failure(.systemError(operation: "listen", code: errno)) }
        return (descriptor, FileIdentity(device: info.st_dev, inode: info.st_ino))
    }

    private static func serverError(for failure: UnixSocket.Failure) -> DeveloperBridgeServerError {
        switch failure {
        case .pathTooLong: .socketPathTooLong
        case .timedOut: .systemError(operation: "connect", code: ETIMEDOUT)
        case .system(let operation, let code): .systemError(operation: operation, code: code)
        }
    }

    // MARK: Connections (on `queue`)

    private func acceptPendingConnections() {
        while !isShutDown {
            let descriptor = accept(listeningDescriptor, nil, nil)
            guard descriptor >= 0 else {
                switch errno {
                case EINTR, ECONNABORTED:
                    continue
                case EMFILE, ENFILE, ENOBUFS, ENOMEM:
                    pauseAccepting()
                    return
                default:  // EAGAIN: nothing left to accept.
                    return
                }
            }
            guard (try? UnixSocket.configure(descriptor)) != nil,
                  DeveloperBridgeServer.allowsPeer(uid: Self.peerUserID(of: descriptor)),
                  connections.count < limits.maxConnections else {
                close(descriptor)
                continue
            }
            open(descriptor)
        }
    }

    private func pauseAccepting() {
        guard let acceptSource, !isAcceptSuspended else { return }
        acceptSource.suspend()
        isAcceptSuspended = true
        queue.asyncAfter(deadline: .now() + Self.acceptRetryDelay) { [weak self] in
            guard let self, isAcceptSuspended, !isShutDown else { return }
            isAcceptSuspended = false
            acceptSource.resume()
        }
    }

    private static func peerUserID(of descriptor: Int32) -> uid_t? {
        var uid = uid_t.max
        var gid = gid_t.max
        return getpeereid(descriptor, &uid, &gid) == 0 ? uid : nil
    }

    private func open(_ descriptor: Int32) {
        lastConnectionID &+= 1
        let id = lastConnectionID
        let readSource = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        readSource.setEventHandler { [weak self] in self?.readAvailableBytes(on: id) }
        // Dispatch requires the descriptor to stay open until its source is cancelled.
        readSource.setCancelHandler { close(descriptor) }
        let deadline = DispatchSource.makeTimerSource(queue: queue)
        deadline.schedule(deadline: .now() + limits.readTimeout, leeway: .milliseconds(100))
        deadline.setEventHandler { [weak self] in self?.finish(id, answering: .failure(.malformed)) }
        connections[id] = Connection(descriptor: descriptor, readSource: readSource, deadline: deadline)
        readSource.resume()
        deadline.resume()
    }

    private func readAvailableBytes(on id: UInt64) {
        guard let connection = connections[id] else { return }
        let limit = DeveloperProtocol.maxMessageBytes
        var chunk = [UInt8](repeating: 0, count: 4096)
        var atEndOfFile = false
        // Never buffers more than `limit + 1` bytes: enough to tell a message from an oversized one.
        reading: while connection.buffer.count <= limit {
            let room = min(chunk.count, limit + 1 - connection.buffer.count)
            let (count, code) = chunk.withUnsafeMutableBytes { (read(connection.descriptor, $0.baseAddress, room), errno) }
            switch count {
            case 1...:
                connection.buffer.append(contentsOf: chunk[..<count])
                if chunk[..<count].contains(UInt8(ascii: "\n")) { break reading }
            case 0:
                atEndOfFile = true
                break reading
            default:
                if code == EINTR { continue }
                if code == EAGAIN { break reading }
                finish(id, answering: nil)
                return
            }
        }
        switch DeveloperBridgeFraming.frame(connection.buffer, limit: limit, atEndOfFile: atEndOfFile) {
        case .incomplete:
            break
        case .tooLarge:
            finish(id, answering: .failure(.tooLarge))
        case .message(let data):
            finish(id, answering: handle(data))
        }
    }

    private func handle(_ data: Data) -> DeveloperBridgeResponse {
        do {
            let message = try DeveloperBridgeMessage.decode(data)
            if message.type != .ping {
                deliver(message)
            }
            return .success
        } catch {
            return .failure(error)
        }
    }

    /// Answers (unless `response` is nil) and closes the connection.
    private func finish(_ id: UInt64, answering response: DeveloperBridgeResponse?) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        if let response, let data = try? DeveloperBridgeFraming.encodeLine(response) {
            Self.writeIfPossible(data, to: connection.descriptor)
        }
        connection.deadline.cancel()
        connection.readSource.cancel()
    }

    /// Writes without waiting. Answers are far smaller than a fresh socket's buffer, so this only
    /// gives up when the client is gone.
    private static func writeIfPossible(_ data: Data, to descriptor: Int32) {
        var offset = 0
        while offset < data.count {
            let count = data[(data.startIndex + offset)...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                offset += count
            } else if count < 0, errno == EINTR {
                continue
            } else {
                return
            }
        }
    }

    /// Cancels every source; their cancel handlers close the descriptors.
    private func cancelSources() {
        if let acceptSource {
            acceptSource.cancel()
            if isAcceptSuspended {
                // A suspended source neither runs its cancel handler nor may be released.
                isAcceptSuspended = false
                acceptSource.resume()
            }
        }
        for connection in connections.values {
            connection.deadline.cancel()
            connection.readSource.cancel()
        }
        connections.removeAll()
    }

    private func removeSocketFile() {
        var info = stat()
        guard lstat(socketPath, &info) == 0,
              FileIdentity(device: info.st_dev, inode: info.st_ino) == socketIdentity else { return }
        unlink(socketPath)
    }
}
