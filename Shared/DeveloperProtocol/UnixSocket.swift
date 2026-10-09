import Darwin
import Foundation

/// POSIX plumbing for the bridge's Unix domain socket, shared by NotchDeck (listening) and
/// `notchctl` (connecting).
///
/// Every socket made here is close-on-exec, non-blocking and never raises `SIGPIPE`. Blocking
/// helpers wait on their one descriptor with `poll(2)` until a deadline, so nothing spins or wakes
/// up periodically.
enum UnixSocket {
    enum Failure: Error, Equatable, Sendable {
        /// The path doesn't fit `sockaddr_un.sun_path`.
        case pathTooLong
        case timedOut
        /// A system call failed with `errno` `code`.
        case system(operation: String, code: Int32)
    }

    /// The path of a file URL as handed to system calls.
    static func path(of url: URL) -> String {
        url.path(percentEncoded: false)
    }

    /// The address of the socket at `path`. Nil when the path is empty, contains a NUL byte or is
    /// longer than `DeveloperBridgeLocation.maxSocketPathBytes`.
    static func address(forPath path: String) -> sockaddr_un? {
        let bytes = Array(path.utf8)
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !bytes.isEmpty, !bytes.contains(0),
              bytes.count <= DeveloperBridgeLocation.maxSocketPathBytes, bytes.count < capacity else { return nil }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }  // the rest stays NUL
        return address
    }

    /// Calls `body` with `address` as a generic `sockaddr` and its length.
    static func withSockaddr<T>(_ address: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var address = address
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    /// A new stream socket, configured with `configure(_:)`.
    static func makeStreamSocket() throws(Failure) -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw .system(operation: "socket", code: errno) }
        do {
            try configure(descriptor)
        } catch {
            close(descriptor)
            throw error
        }
        return descriptor
    }

    /// Makes `descriptor` close-on-exec and non-blocking, and stops writes to a closed peer from
    /// raising `SIGPIPE` (they fail with `EPIPE` instead). Accepted sockets need this too: none of
    /// it is reliably inherited from the listening socket.
    static func configure(_ descriptor: Int32) throws(Failure) {
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            throw .system(operation: "fcntl", code: errno)
        }
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw .system(operation: "fcntl", code: errno)
        }
        var on: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw .system(operation: "setsockopt", code: errno)
        }
    }

    /// Connects the non-blocking `descriptor` to `address`, waiting until `deadline`.
    static func connect(_ descriptor: Int32, to address: sockaddr_un, deadline: ContinuousClock.Instant) throws(Failure) {
        let (result, code) = withSockaddr(address) { (Darwin.connect(descriptor, $0, $1), errno) }
        guard result != 0 else { return }
        guard code == EINPROGRESS || code == EINTR else { throw .system(operation: "connect", code: code) }
        try wait(descriptor, for: Int16(POLLOUT), until: deadline)
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else {
            throw .system(operation: "connect", code: errno)
        }
        guard error == 0 else { throw .system(operation: "connect", code: error) }
    }

    /// Whether something accepts connections at `address` within `timeout`. A busy listener (no
    /// answer in time) counts as listening; a refused connection or a missing file doesn't.
    static func isListening(at address: sockaddr_un, timeout: TimeInterval) -> Bool {
        guard let descriptor = try? makeStreamSocket() else { return false }
        defer { close(descriptor) }
        do {
            try connect(descriptor, to: address, deadline: deadline(after: timeout))
            return true
        } catch .timedOut {
            return true
        } catch {
            return false
        }
    }

    /// Writes all of `data`, waiting for buffer space until `deadline`.
    static func write(_ data: Data, to descriptor: Int32, deadline: ContinuousClock.Instant) throws(Failure) {
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let (count, code) = bytes[offset...].withUnsafeBytes { (Darwin.write(descriptor, $0.baseAddress, $0.count), errno) }
            if count > 0 {
                offset += count
            } else if count < 0, code == EAGAIN {
                try wait(descriptor, for: Int16(POLLOUT), until: deadline)
            } else if count < 0, code == EINTR {
                continue
            } else {
                throw .system(operation: "write", code: count < 0 ? code : EIO)
            }
        }
    }

    /// Reads one frame (see `DeveloperBridgeFraming`) of at most `limit` bytes, waiting until
    /// `deadline`.
    static func readFrame(from descriptor: Int32, limit: Int, deadline: ContinuousClock.Instant) throws(Failure) -> DeveloperBridgeFraming.Frame {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let frame = DeveloperBridgeFraming.frame(buffer, limit: limit, atEndOfFile: false)
            guard frame == .incomplete else { return frame }
            let room = min(chunk.count, limit + 1 - buffer.count)
            let (count, code) = chunk.withUnsafeMutableBytes { (read(descriptor, $0.baseAddress, room), errno) }
            if count > 0 {
                buffer.append(contentsOf: chunk[..<count])
            } else if count == 0 {
                return DeveloperBridgeFraming.frame(buffer, limit: limit, atEndOfFile: true)
            } else if code == EAGAIN {
                try wait(descriptor, for: Int16(POLLIN), until: deadline)
            } else if code != EINTR {
                throw .system(operation: "read", code: code)
            }
        }
    }

    /// Waits until `descriptor` is ready for `events` (or has an error or hang-up, which the next
    /// call reports) or `deadline` passes.
    static func wait(_ descriptor: Int32, for events: Int16, until deadline: ContinuousClock.Instant) throws(Failure) {
        while true {
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { throw .timedOut }
            var poller = pollfd(fd: descriptor, events: events, revents: 0)
            let result = poll(&poller, 1, milliseconds(remaining))
            if result > 0 { return }
            if result < 0, errno != EINTR { throw .system(operation: "poll", code: errno) }
        }
    }

    static func deadline(after timeout: TimeInterval) -> ContinuousClock.Instant {
        .now + .milliseconds(Int(max(0, timeout) * 1000))
    }

    /// `duration` in whole milliseconds, rounded up so a wait never ends just before its deadline.
    private static func milliseconds(_ duration: Duration) -> Int32 {
        let (seconds, attoseconds) = duration.components
        let milliseconds = seconds * 1000 + (attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000
        return Int32(clamping: milliseconds)
    }
}
