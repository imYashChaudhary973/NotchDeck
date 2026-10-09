import Darwin
import Foundation

/// Why a message didn't get an answer from NotchDeck.
enum DeveloperBridgeClientError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The message failed validation; nothing was sent.
    case invalidMessage(DeveloperProtocolError)
    /// Nothing listens at the socket path: NotchDeck isn't running or Developer agents is turned off.
    case notRunning
    /// NotchDeck didn't answer in time.
    case timedOut
    /// The socket path doesn't fit `sockaddr_un` (more than 103 bytes).
    case socketPathTooLong
    /// The connection closed without a well-formed answer, e.g. because NotchDeck turned it away.
    case invalidResponse
    /// Another system error, with its `errno`.
    case connectionFailed(code: Int32)

    var description: String {
        switch self {
        case .invalidMessage(let error): "Invalid message: \(error)"
        case .notRunning: "NotchDeck isn't listening. Is it running, with Settings ▸ Features ▸ Developer agents on?"
        case .timedOut: "NotchDeck didn't answer in time."
        case .socketPathTooLong: "The socket path is longer than \(DeveloperBridgeLocation.maxSocketPathBytes) bytes."
        case .invalidResponse: "NotchDeck closed the connection without a valid answer."
        case .connectionFailed(let code): "Couldn't talk to NotchDeck: \(String(cString: strerror(code)))."
        }
    }
}

/// Sends developer activity messages to NotchDeck's socket. Used by `notchctl`.
///
/// Calls block for at most `timeout`. Each message travels on its own connection (see
/// `DeveloperBridgeFraming`).
enum DeveloperBridgeClient {
    static let defaultTimeout: TimeInterval = 2

    /// Validates `message`, sends it and returns NotchDeck's answer. A response with `ok == false`
    /// means NotchDeck rejected the message.
    static func send(
        _ message: DeveloperBridgeMessage,
        to socketURL: URL = DeveloperBridgeLocation.socketURL,
        timeout: TimeInterval = defaultTimeout
    ) throws(DeveloperBridgeClientError) -> DeveloperBridgeResponse {
        let payload: Data
        do {
            payload = try message.validated().encoded()
        } catch let error as DeveloperProtocolError {
            throw .invalidMessage(error)
        } catch {
            throw .invalidMessage(.malformed)
        }
        return try exchange(payload, with: socketURL, timeout: timeout)
    }

    /// Sends `payload` as one request, adding the terminating newline, and reads the answer. The
    /// bytes are sent as they are; `send(_:to:timeout:)` is the validating entry point.
    static func exchange(_ payload: Data, with socketURL: URL, timeout: TimeInterval) throws(DeveloperBridgeClientError) -> DeveloperBridgeResponse {
        guard let address = UnixSocket.address(forPath: UnixSocket.path(of: socketURL)) else { throw .socketPathTooLong }
        let deadline = UnixSocket.deadline(after: timeout)

        let descriptor: Int32
        do {
            descriptor = try UnixSocket.makeStreamSocket()
        } catch {
            throw Self.error(for: error)
        }
        defer { close(descriptor) }

        do {
            try UnixSocket.connect(descriptor, to: address, deadline: deadline)
        } catch .system(_, let code) where code == ENOENT || code == ENOTDIR || code == ECONNREFUSED {
            throw .notRunning
        } catch {
            throw Self.error(for: error)
        }

        var request = payload
        request.append(UInt8(ascii: "\n"))
        do {
            try UnixSocket.write(request, to: descriptor, deadline: deadline)
            shutdown(descriptor, SHUT_WR)
        } catch .system(_, let code) where code == EPIPE || code == ECONNRESET {
            // NotchDeck stopped reading early (e.g. the request is too large); its answer may
            // already be waiting.
        } catch {
            throw Self.error(for: error)
        }

        let frame: DeveloperBridgeFraming.Frame
        do {
            frame = try UnixSocket.readFrame(from: descriptor, limit: DeveloperProtocol.maxResponseBytes, deadline: deadline)
        } catch .system(_, let code) where code == ECONNRESET {
            throw .invalidResponse
        } catch {
            throw Self.error(for: error)
        }
        guard case .message(let data) = frame,
              let response = try? JSONDecoder().decode(DeveloperBridgeResponse.self, from: data) else {
            throw .invalidResponse
        }
        return response
    }

    private static func error(for failure: UnixSocket.Failure) -> DeveloperBridgeClientError {
        switch failure {
        case .pathTooLong: .socketPathTooLong
        case .timedOut: .timedOut
        case .system(_, let code): .connectionFailed(code: code)
        }
    }
}
