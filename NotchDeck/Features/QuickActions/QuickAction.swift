import AppKit

/// Whether a quick action can run on this Mac.
enum QuickActionAvailability: Equatable, Sendable {
    case available
    /// The capability has no stable public API (or its feature is off). Not shown in the notch.
    case unavailable(reason: String)
}

/// One button in the Quick Actions grid. Conform to add a new action, then list it in
/// `AppEnvironment.makeQuickActions()`.
///
/// Actions must use public APIs only. If macOS offers no supported way to do something, return
/// `.unavailable` (and document why) or use a safe fallback such as opening the relevant app
/// or System Settings pane.
@MainActor
protocol QuickAction {
    /// Stable identifier; also the action ID routed back from the notch.
    var id: String { get }
    var title: String { get }
    var symbolName: String { get }
    var availability: QuickActionAvailability { get }
    /// Highlights the tile (e.g. Keep Awake while it is on).
    var isActive: Bool { get }
    func perform()
}

extension QuickAction {
    var availability: QuickActionAvailability { .available }
    var isActive: Bool { false }
}

/// Opens things through `NSWorkspace`. Abstracted so actions can be tested without side effects.
@MainActor
protocol WorkspaceOpening {
    func open(_ url: URL)
    func applicationURL(bundleIdentifier: String) -> URL?
}

@MainActor
struct SystemWorkspace: WorkspaceOpening {
    func open(_ url: URL) {
        if url.pathExtension == "app" {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}

/// An action backed by closures, for actions that drive another feature (start a timer, Keep Awake).
struct ClosureQuickAction: QuickAction {
    let id: String
    let title: String
    let symbolName: String
    var isAvailable: () -> Bool = { true }
    var isActiveState: () -> Bool = { false }
    let action: () -> Void

    var availability: QuickActionAvailability {
        isAvailable() ? .available : .unavailable(reason: "The feature is turned off in Settings.")
    }

    var isActive: Bool { isActiveState() }

    func perform() { action() }
}

/// Opens a folder in Finder.
struct OpenFolderQuickAction: QuickAction {
    let id: String
    let title: String
    let symbolName: String
    let url: URL?
    let workspace: any WorkspaceOpening

    var availability: QuickActionAvailability {
        url == nil ? .unavailable(reason: "Folder not found.") : .available
    }

    func perform() {
        url.map(workspace.open)
    }

    static func downloads(workspace: any WorkspaceOpening = SystemWorkspace()) -> OpenFolderQuickAction {
        OpenFolderQuickAction(
            id: "openDownloads", title: "Downloads", symbolName: "arrow.down.circle",
            url: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            workspace: workspace
        )
    }

    static func applications(workspace: any WorkspaceOpening = SystemWorkspace()) -> OpenFolderQuickAction {
        OpenFolderQuickAction(
            id: "openApplications", title: "Applications", symbolName: "square.grid.3x3",
            url: FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first,
            workspace: workspace
        )
    }
}

/// Launches an app by bundle identifier.
struct OpenApplicationQuickAction: QuickAction {
    let id: String
    let title: String
    let symbolName: String
    let bundleIdentifier: String
    let workspace: any WorkspaceOpening

    var availability: QuickActionAvailability {
        workspace.applicationURL(bundleIdentifier: bundleIdentifier) == nil
            ? .unavailable(reason: "\(title) is not installed.")
            : .available
    }

    func perform() {
        workspace.applicationURL(bundleIdentifier: bundleIdentifier).map(workspace.open)
    }

    static func activityMonitor(workspace: any WorkspaceOpening = SystemWorkspace()) -> OpenApplicationQuickAction {
        OpenApplicationQuickAction(
            id: "openActivityMonitor", title: "Activity Monitor", symbolName: "waveform.path.ecg",
            bundleIdentifier: "com.apple.ActivityMonitor", workspace: workspace
        )
    }

    /// Opens the system Screenshot app (the ⇧⌘5 toolbar). Capturing directly would need
    /// Screen Recording permission; the system tool needs none.
    static func screenshot(workspace: any WorkspaceOpening = SystemWorkspace()) -> OpenApplicationQuickAction {
        OpenApplicationQuickAction(
            id: "screenshot", title: "Screenshot", symbolName: "camera.viewfinder",
            bundleIdentifier: "com.apple.screenshot.launcher", workspace: workspace
        )
    }

    /// Fallback for locking the screen: starts the screen saver, which locks the Mac when
    /// "Require password after screen saver begins" is on (the default).
    static func screenSaver(workspace: any WorkspaceOpening = SystemWorkspace()) -> OpenApplicationQuickAction {
        OpenApplicationQuickAction(
            id: "screenSaver", title: "Screen Saver", symbolName: "moon.zzz",
            bundleIdentifier: "com.apple.ScreenSaver.Engine", workspace: workspace
        )
    }
}

/// Locking the screen directly has no public API on macOS (the known ways are private
/// frameworks or simulated keystrokes that need Accessibility access), so it is unavailable.
/// `OpenApplicationQuickAction.screenSaver` is the supported fallback.
struct LockScreenQuickAction: QuickAction {
    let id = "lockScreen"
    let title = "Lock Screen"
    let symbolName = "lock.fill"
    let availability = QuickActionAvailability.unavailable(reason: "macOS has no public API to lock the screen.")

    func perform() {}
}
