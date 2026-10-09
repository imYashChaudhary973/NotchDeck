import Foundation

/// How messages travel over the bridge socket.
///
/// One connection carries one exchange: the client sends one JSON object (a
/// `DeveloperBridgeMessage`) ended by a newline or by closing its write side; NotchDeck answers
/// with one `DeveloperBridgeResponse` JSON object and a newline, then closes the connection.
/// Requests are limited to `DeveloperProtocol.maxMessageBytes`, responses to
/// `DeveloperProtocol.maxResponseBytes`; bytes after the newline are ignored.
enum DeveloperBridgeFraming {
    enum Frame: Equatable, Sendable {
        /// More bytes are needed.
        case incomplete
        /// A complete frame, without its newline.
        case message(Data)
        /// More than the limit arrived before a newline.
        case tooLarge
    }

    /// Finds the frame in the bytes received so far. Reading `limit + 1` bytes is enough to decide.
    static func frame(_ buffer: Data, limit: Int, atEndOfFile: Bool) -> Frame {
        if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            return line.count <= limit ? .message(Data(line)) : .tooLarge
        }
        if buffer.count > limit { return .tooLarge }
        return atEndOfFile ? .message(buffer) : .incomplete
    }

    /// `value` as JSON plus the terminating newline.
    static func encodeLine(_ value: some Encodable) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
