import Darwin
import Foundation

/// Why the bridge couldn't start listening. Descriptions never include message content.
enum DeveloperBridgeServerError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The socket path doesn't fit `sockaddr_un` (more than 103 bytes).
    case socketPathTooLong
    /// The socket's directory is a symlink, not a directory, or belongs to another user.
    case unsafeDirectory
    /// Something other than a socket is at the socket path. It is left alone.
    case socketPathOccupied
    /// Another NotchDeck already listens on the socket.
    case alreadyRunning
    /// A system call failed with `errno` `code`.
    case systemError(operation: String, code: Int32)

    var description: String {
        switch self {
        case .socketPathTooLong: "The developer bridge socket path is longer than \(DeveloperBridgeLocation.maxSocketPathBytes) bytes."
        case .unsafeDirectory: "The developer bridge directory isn't a private directory owned by you."
        case .socketPathOccupied: "A file that isn't a socket is in the way of the developer bridge socket."
        case .alreadyRunning: "Another NotchDeck is already listening for developer activity."
        case .systemError(let operation, let code): "The developer bridge failed (\(operation): \(String(cString: strerror(code))))."
        }
    }
}

/// Listens on the bridge's Unix domain socket for messages from `notchctl`; the wire format is
/// described in `DeveloperBridgeFraming`.
///
/// Security: the socket is mode 0600 inside a 0700 directory owned by the user, and a connection
/// is closed unread unless its peer runs as the same user (`getpeereid`). There is no network
/// listener. Requests are bounded in size, time and number of open connections, and decoded as
/// untrusted input. Message contents are never logged.
///
/// Event-driven: dispatch sources wake the private queue only when a client connects or sends
/// data, so an idle bridge costs nothing. Valid `event` and `end` messages are delivered on the
/// main actor in the order they arrive; pings are answered here.
@MainActor
final class DeveloperBridgeServer: DeveloperEventSource {
    struct Limits: Sendable {
        /// How long a client has to send its message.
        var readTimeout: TimeInterval = 2
        /// Connections open at once; more are closed at once.
        var maxConnections = 8
        /// Pending connections the system queues before refusing more.
        var backlog: Int32 = 8
    }

    let socketURL: URL
    private let limits: Limits
    private var listener: DeveloperBridgeListener?
    private var onMessage: (@MainActor (DeveloperBridgeMessage) -> Void)?
    /// Changes with every start, so messages a stopped listener accepted are dropped.
    private var generation = 0

    init(socketURL: URL = DeveloperBridgeLocation.socketURL, limits: Limits = Limits()) {
        self.socketURL = socketURL
        self.limits = limits
    }

    var isListening: Bool { listener != nil }

    /// Creates the socket and starts accepting connections. While already listening, only replaces
    /// the handler. Throws `DeveloperBridgeServerError`.
    func start(onMessage: @escaping @MainActor (DeveloperBridgeMessage) -> Void) throws {
        guard listener == nil else {
            self.onMessage = onMessage
            return
        }
        generation += 1
        let generation = generation
        let listener = try DeveloperBridgeListener(socketURL: socketURL, limits: limits) { [weak self] message in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == generation else { return }
                    self.onMessage?(message)
                }
            }
        }
        self.onMessage = onMessage
        self.listener = listener
        listener.resume()
    }

    /// Stops listening: closes every connection and removes the socket file if it is still the one
    /// this server created. The directory stays. Safe to call when not listening.
    func stop() {
        guard let listener else { return }
        self.listener = nil
        onMessage = nil
        generation += 1
        listener.shutDown()
    }

    /// Whether a connecting process may use the bridge: only processes running as the same user
    /// as NotchDeck. `peerUID` is nil when the system couldn't tell.
    nonisolated static func allowsPeer(uid peerUID: uid_t?, ownUID: uid_t = getuid()) -> Bool {
        peerUID == ownUID
    }
}
