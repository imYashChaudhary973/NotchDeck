import Foundation

/// Where NotchDeck listens for developer activity messages.
///
/// The socket lives in a directory only the user can enter (mode 0700), so other users can't reach
/// it; the app also checks each peer's user ID. There is no network listener of any kind.
enum DeveloperBridgeLocation {
    /// Overrides the socket path for `notchctl` (tests, development). The app never reads it.
    static let socketEnvironmentKey = "NOTCHDECK_SOCKET"

    /// `sockaddr_un.sun_path` holds 104 bytes, including the terminating NUL.
    static let maxSocketPathBytes = 103

    /// `~/Library/Application Support/NotchDeck/Bridge`.
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "NotchDeck/Bridge", directoryHint: .isDirectory)
    }

    /// `~/Library/Application Support/NotchDeck/Bridge/bridge.sock`.
    static var socketURL: URL {
        directory.appending(path: "bridge.sock", directoryHint: .notDirectory)
    }

    /// The socket `notchctl` connects to: `NOTCHDECK_SOCKET` when set, otherwise `socketURL`.
    static func clientSocketURL(environment: [String: String]) -> URL {
        if let override = environment[socketEnvironmentKey], override.hasPrefix("/") {
            return URL(filePath: override, directoryHint: .notDirectory)
        }
        return socketURL
    }
}

/// Guesses which app (terminal or editor) the current process runs in, so NotchDeck can bring it
/// forward later. Only a hint: it is validated by the protocol and checked against known apps by
/// NotchDeck before use.
enum TerminalHint {
    /// `TERM_PROGRAM` values of common terminals and editors.
    static let termProgramBundleIDs: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm",
        "Hyper": "co.zeit.hyper",
        "Tabby": "org.tabby",
        "vscode": "com.microsoft.VSCode",
        "zed": "dev.zed.Zed",
    ]

    /// `__CFBundleIdentifier` (set by macOS for processes started from an app, inherited by
    /// shells), otherwise a known `TERM_PROGRAM`. Nil when neither gives a plausible bundle ID.
    static func bundleIdentifier(environment: [String: String]) -> String? {
        if let bundleID = environment["__CFBundleIdentifier"], isPlausibleBundleIdentifier(bundleID) {
            return bundleID
        }
        if let program = environment["TERM_PROGRAM"], let bundleID = termProgramBundleIDs[program] {
            return bundleID
        }
        return nil
    }

    static func isPlausibleBundleIdentifier(_ value: String) -> Bool {
        DeveloperBridgeMessage.isValidBundleIdentifier(value) && value.contains(".")
    }
}
