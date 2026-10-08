import Foundation
import CoreServices

/// The result of a script: its text value, or its raw data (such as artwork bytes).
struct AppleScriptOutput: Sendable {
    var text: String?
    var data: Data?
}

enum AppleScriptFailure: Error, Equatable, Sendable {
    /// The user has not allowed NotchDeck to control the app (System Settings ▸ Privacy ▸ Automation).
    case notPermitted
    case failed(code: Int)
}

/// Runs AppleScript (Apple Events) against scriptable media apps, off the main thread.
///
/// Apple Events are the supported way to read and control Music and Spotify. The first event sent to
/// an app asks the user for Automation permission; scripts wait for that answer, which is why they
/// never run on the main thread. Every script has its own `with timeout`, so a hung app can't stall
/// the queue for long.
enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "com.imyashchaudhary.NotchDeck.applescript", qos: .userInitiated)

    /// `errAEEventNotPermitted`: the user denied Automation access.
    static let notPermittedCode = -1743

    static func run(_ source: String) async -> Result<AppleScriptOutput, AppleScriptFailure> {
        await withCheckedContinuation { continuation in
            queue.async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .failure(.failed(code: 0)))
                    return
                }
                let descriptor = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
                    continuation.resume(returning: .failure(code == notPermittedCode ? .notPermitted : .failed(code: code)))
                    return
                }
                let text = descriptor.descriptorType == typeNull ? nil : descriptor.stringValue
                continuation.resume(returning: .success(AppleScriptOutput(text: text, data: descriptor.data)))
            }
        }
    }

    /// Whether NotchDeck may send Apple Events to the app, without asking the user.
    /// Returns nil when it can't be determined (for example, the app isn't running).
    static func automationAccess(bundleIdentifier: String) async -> MediaControlAccess? {
        await withCheckedContinuation { continuation in
            queue.async {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
                let status = AEDeterminePermissionToAutomateTarget(
                    target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false
                )
                let access: MediaControlAccess? = switch Int(status) {
                case Int(noErr): .granted
                case notPermittedCode: .denied
                case Int(errAEEventWouldRequireUserConsent): .undetermined
                default: nil
                }
                continuation.resume(returning: access)
            }
        }
    }
}
