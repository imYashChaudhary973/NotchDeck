import Foundation
import Testing
@testable import NotchDeck

private func decode(_ json: String) throws(DeveloperProtocolError) -> DeveloperBridgeMessage {
    try DeveloperBridgeMessage.decode(Data(json.utf8))
}

/// A valid event with one extra JSON member, e.g. `"session":"abc"`.
private func event(_ member: String) -> String {
    #"{"provider":"claude-code","status":"working",\#(member)}"#
}

struct DeveloperBridgeMessageDecodingTests {
    @Test func decodesMinimalEventWithDefaults() throws {
        let message = try decode(#"{"provider":"claude-code","status":"working"}"#)
        #expect(message == DeveloperBridgeMessage(version: 1, type: .event, provider: "claude-code", status: .working))
    }

    @Test func decodesEveryField() throws {
        let message = try decode("""
            {"version":1,"type":"event","provider":"codex","providerName":"Codex","session":"s-1",
             "project":"Rove","workspace":"/Users/me/Rove","task":"Implement tabs","status":"needsInput",
             "message":"Approve the plan?","progress":0.5,"terminal":"com.apple.Terminal"}
            """)
        #expect(message == DeveloperBridgeMessage(
            provider: "codex", providerName: "Codex", session: "s-1", project: "Rove",
            workspace: "/Users/me/Rove", task: "Implement tabs", status: .needsInput,
            message: "Approve the plan?", progress: 0.5, terminal: "com.apple.Terminal"
        ))
    }

    @Test func pingIgnoresEveryOtherField() throws {
        let message = try decode(#"{"type":"ping","provider":"Not Valid!","workspace":"relative","progress":7}"#)
        #expect(message == DeveloperBridgeMessage(type: .ping))
        #expect(message.sessionKey == nil)
    }

    @Test func endNeedsNoStatusAndDropsStatusAndProgress() throws {
        #expect(try decode(#"{"type":"end","provider":"codex"}"#) == DeveloperBridgeMessage(type: .end, provider: "codex"))
        let message = try decode(#"{"type":"end","provider":"codex","status":"working","progress":0.5}"#)
        #expect(message.status == nil)
        #expect(message.progress == nil)
    }

    @Test(arguments: [
        (#"{"status":"working"}"#, DeveloperProtocolError.missingField("provider")),
        (#"{"provider":"   ","status":"working"}"#, .missingField("provider")),
        (#"{"provider":"","status":"working"}"#, .missingField("provider")),
        (#"{"provider":"codex"}"#, .missingField("status")),
        (#"{"type":"end"}"#, .missingField("provider")),
    ])
    func rejectsMissingFields(json: String, expected: DeveloperProtocolError) {
        #expect(throws: expected) { try decode(json) }
    }

    @Test(arguments: [
        #"{"provider":"codex","status":"thinking"}"#,         // unknown status
        #"{"provider":"codex","status":"Working"}"#,          // statuses are case-sensitive
        #"{"provider":"codex","status":"working","type":"launch"}"#,
        #"{"provider":"codex","status":"working","version":"1"}"#,
        #"{"provider":"codex","status":"working","version":1.5}"#,
        #"{"provider":5,"status":"working"}"#,
        #"{"provider":"codex","status":["working"]}"#,
        #"{"provider":"codex","status":"working","progress":"half"}"#,
        #"{"provider":"codex","status":"working","message":{"text":"hi"}}"#,
        #"{"provider":"codex","status":"working","session":42}"#,
    ])
    func rejectsWrongTypesAsMalformed(json: String) {
        #expect(throws: DeveloperProtocolError.malformed) { try decode(json) }
    }

    @Test(arguments: ["[]", #"[{"provider":"codex","status":"working"}]"#, #""text""#, "42", "null", "true", "", "   ", "{", "hello", "{provider: codex}"])
    func rejectsInputThatIsNotAJSONObject(json: String) {
        #expect(throws: DeveloperProtocolError.malformed) { try decode(json) }
    }

    @Test func rejectsInvalidUTF8AndBinaryGarbage() {
        #expect(throws: DeveloperProtocolError.malformed) { try DeveloperBridgeMessage.decode(Data([0x7B, 0xFF, 0xFE, 0x7D])) }
        #expect(throws: DeveloperProtocolError.malformed) { try DeveloperBridgeMessage.decode(Data([0x00, 0x01, 0x02, 0x9F])) }
        #expect(throws: DeveloperProtocolError.malformed) { try DeveloperBridgeMessage.decode(Data()) }
    }

    @Test func rejectsDeeplyNestedValuesWithoutCrashing() {
        let depth = 7_000
        let json = event(#""extra":"# + String(repeating: "[", count: depth) + String(repeating: "]", count: depth))
        #expect(json.utf8.count <= DeveloperProtocol.maxMessageBytes)
        #expect(throws: DeveloperProtocolError.malformed) { try decode(json) }
    }

    @Test func rejectsMessagesOverTheSizeLimitBeforeDecoding() {
        let padding = String(repeating: "a", count: DeveloperProtocol.maxMessageBytes)
        #expect(throws: DeveloperProtocolError.tooLarge) { try decode(event(#""message":"\#(padding)""#)) }
        // Too large is decided on size alone, even for garbage.
        #expect(throws: DeveloperProtocolError.tooLarge) {
            try DeveloperBridgeMessage.decode(Data(repeating: 0xFF, count: DeveloperProtocol.maxMessageBytes + 1))
        }
    }

    @Test func acceptsAMessageOfExactlyTheLimit() throws {
        let json = #"{"provider":"codex","status":"working"}"#
        let padded = json + String(repeating: " ", count: DeveloperProtocol.maxMessageBytes - json.utf8.count)
        #expect(padded.utf8.count == DeveloperProtocol.maxMessageBytes)
        #expect(try decode(padded).provider == "codex")
    }

    @Test func ignoresUnknownKeys() throws {
        let message = try decode(event(#""future":{"nested":[1,2,{"x":null}]},"color":"red""#))
        #expect(message == DeveloperBridgeMessage(provider: "claude-code", status: .working))
    }
}

struct DeveloperBridgeMessageValidationTests {
    @Test func rejectsVersionsItDoesNotSpeak() {
        #expect(throws: DeveloperProtocolError.invalidField("version")) { try decode(event(#""version":0"#)) }
        #expect(throws: DeveloperProtocolError.invalidField("version")) { try decode(event(#""version":-1"#)) }
        #expect(throws: DeveloperProtocolError.unsupportedVersion(2)) { try decode(event(#""version":2"#)) }
        #expect(throws: DeveloperProtocolError.unsupportedVersion(2)) { try decode(#"{"version":2,"type":"ping"}"#) }
    }

    @Test func normalizesTheProvider() throws {
        #expect(try decode(#"{"provider":"Claude-Code","status":"working"}"#).provider == "claude-code")
        #expect(try decode(#"{"provider":" codex ","status":"working"}"#).provider == "codex")
        #expect(try decode(#"{"provider":"my.tool_2-x","status":"working"}"#).provider == "my.tool_2-x")
        let longest = String(repeating: "a", count: DeveloperProtocol.maxProviderLength)
        #expect(try decode(#"{"provider":"\#(longest)","status":"working"}"#).provider == longest)
    }

    @Test(arguments: ["my tool", "🤖", "tool🤖", "-tool", ".tool", "_tool", "tool/x", "tool:x", "äbc", "a\\nb",
                      String(repeating: "a", count: DeveloperProtocol.maxProviderLength + 1)])
    func rejectsInvalidProviders(provider: String) {
        #expect(throws: DeveloperProtocolError.invalidField("provider")) {
            try decode(#"{"provider":"\#(provider)","status":"working"}"#)
        }
    }

    @Test(arguments: ["8f1c2d", "AB-12_x.y:z@w+v=u/t", String(repeating: "s", count: DeveloperProtocol.maxSessionLength)])
    func acceptsSessionIDs(session: String) throws {
        #expect(try decode(event(#""session":"\#(session)""#)).session == session)
    }

    @Test(arguments: ["", "has space", "semi;colon", "quote'", "ünï", "tab\\t", String(repeating: "s", count: DeveloperProtocol.maxSessionLength + 1)])
    func rejectsInvalidSessionIDs(session: String) {
        #expect(throws: DeveloperProtocolError.invalidField("session")) { try decode(event(#""session":"\#(session)""#)) }
    }

    @Test(arguments: ["com.apple.Terminal", "dev.warp.Warp-Stable", "com.googlecode.iterm2"])
    func acceptsBundleIdentifiers(terminal: String) throws {
        #expect(try decode(event(#""terminal":"\#(terminal)""#)).terminal == terminal)
    }

    @Test(arguments: ["", "com apple", ".com.apple", "com_apple.x", "com.apple/Terminal", "file:///Applications",
                      String(repeating: "a", count: DeveloperProtocol.maxTerminalLength + 1)])
    func rejectsInvalidBundleIdentifiers(terminal: String) {
        #expect(throws: DeveloperProtocolError.invalidField("terminal")) { try decode(event(#""terminal":"\#(terminal)""#)) }
    }

    @Test func standardizesTheWorkspace() throws {
        #expect(try decode(event(#""workspace":"/Users/me/../me/Rove/./""#)).workspace == "/Users/me/Rove")
        #expect(try decode(event(#""workspace":"/""#)).workspace == "/")
    }

    @Test(arguments: ["Rove", "./Rove", "~/Rove", "", "/Users/me/Rove\\n", "/Users/\\u0000/Rove", "/Users/me\\u001b[31m",
                      "/" + String(repeating: "a", count: DeveloperProtocol.maxPathLength)])
    func rejectsRelativeOrControlCharacterWorkspaces(workspace: String) {
        #expect(throws: DeveloperProtocolError.invalidField("workspace")) { try decode(event(#""workspace":"\#(workspace)""#)) }
    }

    @Test(arguments: [0.0, 0.25, 1.0])
    func acceptsProgressInRange(progress: Double) throws {
        #expect(try decode(event(#""progress":\#(progress)"#)).progress == progress)
    }

    @Test(arguments: ["-0.01", "1.01", "100", "-1e9"])
    func rejectsProgressOutOfRange(progress: String) {
        #expect(throws: DeveloperProtocolError.invalidField("progress")) { try decode(event(#""progress":\#(progress)"#)) }
    }

    @Test func rejectsNonFiniteProgress() {
        for progress in [Double.nan, .infinity, -.infinity] {
            #expect(throws: DeveloperProtocolError.invalidField("progress")) {
                try DeveloperBridgeMessage(provider: "codex", status: .working, progress: progress).validated()
            }
        }
    }

    @Test func sanitizesText() throws {
        let message = try decode(event(#""message":"Line one\nLine two\r\n\t three","task":"  padded  ","project":"a‮b""#))
        #expect(message.message == "Line one Line two three")
        #expect(message.task == "padded")
        #expect(message.project == "a b")
    }

    @Test func removesBidirectionalAndInvisibleFormatting() {
        #expect(DeveloperBridgeMessage.sanitizedText("\u{202E}evil", maxLength: 50) == "evil")
        #expect(DeveloperBridgeMessage.sanitizedText("\u{2066}isolated\u{2069}", maxLength: 50) == "isolated")
        #expect(DeveloperBridgeMessage.sanitizedText("zero\u{200B}width", maxLength: 50) == "zero width")
        #expect(DeveloperBridgeMessage.sanitizedText("bell\u{7}", maxLength: 50) == "bell")
        // Emoji sequences keep their joiners.
        #expect(DeveloperBridgeMessage.sanitizedText("👨‍💻 coding", maxLength: 50) == "👨‍💻 coding")
    }

    @Test func truncatesLongTextWithAnEllipsis() throws {
        let message = try decode(event(#""message":"\#(String(repeating: "x", count: 300))","project":"\#(String(repeating: "p", count: 100))""#))
        #expect(message.message == String(repeating: "x", count: DeveloperProtocol.maxTextLength - 1) + "…")
        #expect(message.project?.count == DeveloperProtocol.maxNameLength)
        #expect(message.project?.hasSuffix("…") == true)
        #expect(DeveloperBridgeMessage.sanitizedText("exactly", maxLength: 7) == "exactly")
    }

    @Test func dropsTextThatIsOnlyWhitespaceOrFormatting() throws {
        let message = try decode(event(#""message":"  \n\t ","task":"‮​","providerName":"""#))
        #expect(message.message == nil)
        #expect(message.task == nil)
        #expect(message.providerName == nil)
    }

    @Test func sessionKeyPrefersSessionThenWorkspaceThenProject() {
        let full = DeveloperBridgeMessage(provider: "codex", session: "s1", project: "Rove", workspace: "/w/Rove", status: .working)
        #expect(full.sessionKey == "codex|session:s1")
        var message = full
        message.session = nil
        #expect(message.sessionKey == "codex|workspace:/w/Rove")
        message.workspace = nil
        #expect(message.sessionKey == "codex|project:Rove")
        message.project = nil
        #expect(message.sessionKey == "codex|default")
        message.provider = nil
        #expect(message.sessionKey == nil)
    }

    @Test func encodedMessagesDecodeToThemselves() throws {
        let message = DeveloperBridgeMessage(provider: "codex", session: "s1", project: "Rove", workspace: "/w/Rove",
                                             task: "Tabs", status: .runningCommand, message: "npm test", progress: 0.4,
                                             terminal: "com.apple.Terminal")
        let data = try message.encoded()
        #expect(!data.contains(UInt8(ascii: "\n")))
        #expect(try DeveloperBridgeMessage.decode(data) == message)
    }
}

struct DeveloperBridgeFramingTests {
    private let limit = 8

    @Test func aNewlineEndsTheFrame() {
        #expect(DeveloperBridgeFraming.frame(Data("abc\ndef".utf8), limit: limit, atEndOfFile: false) == .message(Data("abc".utf8)))
        #expect(DeveloperBridgeFraming.frame(Data("\n".utf8), limit: limit, atEndOfFile: false) == .message(Data()))
    }

    @Test func endOfFileEndsTheFrame() {
        #expect(DeveloperBridgeFraming.frame(Data("abc".utf8), limit: limit, atEndOfFile: false) == .incomplete)
        #expect(DeveloperBridgeFraming.frame(Data("abc".utf8), limit: limit, atEndOfFile: true) == .message(Data("abc".utf8)))
        #expect(DeveloperBridgeFraming.frame(Data(), limit: limit, atEndOfFile: true) == .message(Data()))
    }

    @Test func framesOverTheLimitAreTooLarge() {
        #expect(DeveloperBridgeFraming.frame(Data("12345678\n".utf8), limit: limit, atEndOfFile: false) == .message(Data("12345678".utf8)))
        #expect(DeveloperBridgeFraming.frame(Data("123456789".utf8), limit: limit, atEndOfFile: false) == .tooLarge)
        #expect(DeveloperBridgeFraming.frame(Data("123456789\n".utf8), limit: limit, atEndOfFile: false) == .tooLarge)
        #expect(DeveloperBridgeFraming.frame(Data("123456789".utf8), limit: limit, atEndOfFile: true) == .tooLarge)
    }

    @Test func responsesAreOneLineOfJSON() throws {
        let data = try DeveloperBridgeFraming.encodeLine(DeveloperBridgeResponse.failure(.missingField("provider")))
        #expect(data.last == UInt8(ascii: "\n"))
        #expect(data.filter { $0 == UInt8(ascii: "\n") }.count == 1)
        let decoded = try JSONDecoder().decode(DeveloperBridgeResponse.self, from: data.dropLast())
        #expect(decoded == DeveloperBridgeResponse(ok: false, version: 1, error: "Missing required field 'provider'."))
    }
}
