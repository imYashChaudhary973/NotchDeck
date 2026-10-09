import AppKit

/// Brings an agent session's terminal forward or opens its workspace. Abstracted so the provider
/// can be tested without side effects.
///
/// Callers pass only validated input: known bundle identifiers (`DeveloperApps`) and existing
/// directories (`DeveloperWorkspaceValidator`).
@MainActor
protocol DeveloperWorkspaceOpening {
    /// Whether an app with this bundle identifier is running.
    func isRunning(bundleIdentifier: String) -> Bool
    /// Brings a running app forward.
    func activate(bundleIdentifier: String)
    /// Opens a Terminal window in `directory`.
    func openInTerminal(_ directory: URL)
    /// Opens `directory` in Finder.
    func openInFinder(_ directory: URL)
}

@MainActor
struct SystemDeveloperWorkspace: DeveloperWorkspaceOpening {
    static let terminalBundleID = "com.apple.Terminal"

    func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    func activate(bundleIdentifier: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.activate()
    }

    func openInTerminal(_ directory: URL) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.terminalBundleID) else { return }
        NSWorkspace.shared.open([directory], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    func openInFinder(_ directory: URL) {
        NSWorkspace.shared.open(directory)
    }
}

/// Terminals and editors an agent session may run in. A session's `terminal` comes from another
/// process, so only these apps are ever brought forward.
enum DeveloperApps {
    static let knownBundleIDs: Set<String> = [
        // Terminals
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp-Preview",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "org.tabby",
        // Editors and IDEs
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf",
        "dev.zed.Zed",
        "dev.zed.Zed-Preview",
        "com.apple.dt.Xcode",
        "com.panic.Nova",
        "com.sublimetext.4",
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce",
        "com.jetbrains.WebStorm",
        "com.jetbrains.goland",
        "com.jetbrains.rider",
        "com.jetbrains.CLion",
        "com.jetbrains.rubymine",
        "com.jetbrains.PhpStorm",
        "com.google.android.studio",
    ]

    static func isKnown(_ bundleID: String) -> Bool {
        knownBundleIDs.contains(bundleID)
    }
}

/// Checks workspace paths received from other processes before anything is opened.
enum DeveloperWorkspaceValidator {
    /// The directory at `path` if it is safe to open: an absolute path to an existing directory
    /// (after resolving symbolic links) that isn't a package such as an app. Nil otherwise.
    static func directory(atPath path: String?) -> URL? {
        guard let path, path.hasPrefix("/") else { return nil }
        let url = URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        // Opening a package (e.g. an .app) would launch it rather than show a folder.
        guard (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true else { return nil }
        return url
    }
}
