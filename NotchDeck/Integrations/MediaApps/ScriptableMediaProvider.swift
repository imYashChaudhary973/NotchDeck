import AppKit

/// A `MediaProvider` for a scriptable media app (Apple Music, Spotify) using only supported APIs:
///
/// - **Distributed notifications** the app posts on every playback change give the track and state
///   with no permission and no polling.
/// - **Apple Events** (AppleScript) read the position and artwork and send play/pause/next/previous.
///   They need the user's Automation permission, which macOS asks for the first time the user presses
///   a control. Until then the provider only reads; if the user declines, controls are hidden.
///
/// Scripts run only while the app is running, so NotchDeck never launches a media app.
/// Private frameworks (MediaRemote) are deliberately not used, so other apps' playback (browsers,
/// podcasts) is not shown.
@MainActor
final class ScriptableMediaProvider: NSObject, MediaProvider {
    let app: any ScriptableMediaApp
    private(set) var nowPlaying: NowPlaying?
    private(set) var controlAccess: MediaControlAccess = .undetermined

    private var onChange: (@MainActor () -> Void)?
    private var isObserving = false
    /// Increments on every change, so results of slower script reads that are out of date are dropped.
    private var generation = 0
    private var artworkTrackID: String?

    init(app: any ScriptableMediaApp) {
        self.app = app
    }

    var id: String { app.id }
    var name: String { app.name }
    var symbolName: String { app.symbolName }
    var accent: ActivityAccent { app.accent }

    var capabilities: MediaCapabilities {
        switch controlAccess {
        case .granted: .all
        // Controls are offered: pressing one asks for permission.
        case .undetermined: app.capabilitiesWithoutAutomation.union(.controls)
        case .denied: app.capabilitiesWithoutAutomation
        }
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    // MARK: MediaProvider

    func startObserving(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard !isObserving else { return }
        isObserving = true
        // Accessory apps are almost never active; without `.deliverImmediately` notifications would
        // be held until NotchDeck became active.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playbackChanged(_:)), name: app.notificationName,
            object: nil, suspensionBehavior: .deliverImmediately
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(applicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
        // Pick up what is already playing, if NotchDeck may read it without asking.
        Task { await self.readInitialState() }
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        onChange = nil
        generation += 1
        nowPlaying = nil
        artworkTrackID = nil
    }

    func send(_ command: MediaCommand) {
        guard isRunning else { return }
        let script = app.script(for: command)
        Task {
            let result = await AppleScriptRunner.run(script)
            switch result {
            case .success:
                setAccess(.granted)
                // The app's notification follows; read the state too for the position and artwork.
                await readState()
            case .failure(.notPermitted):
                setAccess(.denied)
            case .failure:
                break
            }
        }
    }

    func refresh() {
        guard controlAccess == .granted, isRunning else { return }
        Task { await readState() }
    }

    // MARK: Notifications

    @objc private func playbackChanged(_ notification: Notification) {
        let date = Date.now
        guard let update = app.nowPlaying(fromNotification: notification.userInfo ?? [:], at: date) else {
            apply(nil)
            return
        }
        var merged = update
        if let current = nowPlaying, current.isSameTrack(as: update) {
            merged.artwork = current.artwork
            // Music doesn't include the position: carry it forward across play/pause.
            if merged.position == nil, let position = current.position(at: date) {
                merged.position = position
            }
            if merged.trackID == nil { merged.trackID = current.trackID }
        }
        apply(merged)
        if controlAccess == .granted {
            Task { await readState() }
        }
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        let terminated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard terminated?.bundleIdentifier == app.bundleIdentifier else { return }
        apply(nil)
    }

    // MARK: Scripts

    private func readInitialState() async {
        guard isRunning, let access = await AppleScriptRunner.automationAccess(bundleIdentifier: app.bundleIdentifier) else { return }
        setAccess(access)
        if access == .granted { await readState() }
    }

    private func readState() async {
        guard isObserving, isRunning else { return }
        let expected = generation
        let result = await AppleScriptRunner.run(app.stateScript)
        // A notification arrived meanwhile; it is newer than this read.
        guard expected == generation else { return }
        switch result {
        case .success(let output):
            setAccess(.granted)
            guard let text = output.text, let (read, artworkURL) = ScriptFields.nowPlaying(from: text, at: .now) else {
                apply(nil)
                return
            }
            var merged = read
            if let current = nowPlaying, current.isSameTrack(as: read) {
                merged.artwork = current.artwork
            }
            apply(merged)
            loadArtworkIfNeeded(artworkURL: artworkURL)
        case .failure(.notPermitted):
            setAccess(.denied)
        case .failure:
            break
        }
    }

    private func loadArtworkIfNeeded(artworkURL: URL?) {
        guard let track = nowPlaying, track.artwork == nil else { return }
        let trackKey = track.trackID ?? track.title
        guard artworkTrackID != trackKey else { return }
        artworkTrackID = trackKey
        let source = app.artworkSource
        Task {
            let artwork: Data? = switch source {
            case .scriptData(let script):
                if case .success(let output) = await AppleScriptRunner.run(script), let data = output.data, !data.isEmpty {
                    await ArtworkLoader.thumbnail(from: data)
                } else {
                    nil
                }
            case .url(let hosts):
                if let artworkURL { await ArtworkLoader.download(artworkURL, allowedHosts: hosts) } else { nil }
            }
            guard let artwork, var current = nowPlaying, (current.trackID ?? current.title) == trackKey else { return }
            current.artwork = artwork
            apply(current)
        }
    }

    // MARK: State

    private func apply(_ value: NowPlaying?) {
        generation += 1
        if value == nil { artworkTrackID = nil }
        guard value != nowPlaying else { return }
        nowPlaying = value
        onChange?()
    }

    private func setAccess(_ access: MediaControlAccess) {
        guard access != controlAccess else { return }
        controlAccess = access
        onChange?()
    }
}
