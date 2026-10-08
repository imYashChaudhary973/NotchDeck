import Foundation

/// Now Playing: the track playing in a supported media app, with playback controls.
///
/// The provider aggregates any number of `MediaProvider`s (Apple Music, Spotify) and shows the one
/// the user is listening to: the player that most recently started playing, otherwise the one most
/// recently paused. Playing music is a Passive (20) Live Activity, so anything more urgent, such as
/// an imminent meeting, interrupts it and music returns automatically afterwards. Paused music
/// moves to the command center, so it never keeps the notch occupied.
///
/// Event-driven: media providers report changes; nothing polls.
@MainActor
final class MusicProvider: ActivityProvider {
    let source = ActivitySource(rawValue: "music")
    static let activityID = "nowPlaying"
    /// Paused music leads the command center (above Quick Actions, 20), so pausing from the
    /// featured card doesn't replace the card.
    static let pausedPriority = ActivityPriority(rawValue: 22)
    static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    enum ActionID {
        static let playPause = "playPause"
        static let next = "next"
        static let previous = "previous"
        static let allowControl = "allowControl"
    }

    let players: [any MediaProvider]
    /// The player currently shown, if any.
    private(set) var activePlayerID: String?

    private var publisher: ActivityPublisher?
    private let workspace: any WorkspaceOpening
    private let now: () -> Date
    /// When each player last started playing (or changed track while playing); picks the active one.
    private var lastPlayed: [String: Date] = [:]
    private var lastPaused: [String: Date] = [:]
    private var lastStates: [String: PlaybackState] = [:]
    private var isDisplayed = false

    init(players: [any MediaProvider], workspace: any WorkspaceOpening = SystemWorkspace(), now: @escaping () -> Date = { .now }) {
        self.players = players
        self.workspace = workspace
        self.now = now
    }

    // MARK: ActivityProvider

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
        for player in players {
            player.startObserving { [weak self] in self?.playerChanged(player.id) }
            noteState(of: player)
        }
        publish()
    }

    func stop() {
        players.forEach { $0.stopObserving() }
        publisher = nil
        activePlayerID = nil
        isDisplayed = false
    }

    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
        guard let player = activePlayer else { return }
        switch actionID {
        case ActionID.playPause: player.send(.playPause)
        case ActionID.next: player.send(.nextTrack)
        case ActionID.previous: player.send(.previousTrack)
        case ActionID.allowControl: workspace.open(Self.automationSettingsURL)
        default: break
        }
    }

    func displayedActivitiesChanged(_ ids: Set<NotchActivity.ID>) {
        let displayed = ids.contains(Self.activityID)
        defer { isDisplayed = displayed }
        // Players don't announce seeks; resynchronize the position when it comes into view.
        if displayed, !isDisplayed, let player = activePlayer, player.capabilities.contains(.progress) {
            player.refresh()
        }
    }

    // MARK: State

    private var activePlayer: (any MediaProvider)? {
        players.first { $0.id == activePlayerID }
    }

    private func playerChanged(_ id: String) {
        if let player = players.first(where: { $0.id == id }) {
            noteState(of: player)
        }
        publish()
    }

    private func noteState(of player: any MediaProvider) {
        let state = player.nowPlaying?.state ?? .stopped
        if state != lastStates[player.id] {
            switch state {
            case .playing: lastPlayed[player.id] = now()
            case .paused: lastPaused[player.id] = now()
            case .stopped: break
            }
            lastStates[player.id] = state
        }
    }

    /// Chooses the player to show: the most recently started playing one, otherwise the most
    /// recently paused one. Stopped players are never shown.
    static func activePlayerID(
        states: [(id: String, state: PlaybackState?)],
        lastPlayed: [String: Date],
        lastPaused: [String: Date]
    ) -> String? {
        func latest(_ state: PlaybackState, by dates: [String: Date]) -> String? {
            states.filter { $0.state == state }
                .max { (dates[$0.id] ?? .distantPast) < (dates[$1.id] ?? .distantPast) }?
                .id
        }
        return latest(.playing, by: lastPlayed) ?? latest(.paused, by: lastPaused)
    }

    private func publish() {
        activePlayerID = Self.activePlayerID(
            states: players.map { ($0.id, $0.nowPlaying?.state) },
            lastPlayed: lastPlayed,
            lastPaused: lastPaused
        )
        guard let publisher else { return }
        if let player = activePlayer, let nowPlaying = player.nowPlaying {
            publisher.publish(Self.activity(
                for: nowPlaying,
                playerName: player.name,
                symbolName: player.symbolName,
                accent: player.accent,
                capabilities: player.capabilities,
                controlAccess: player.controlAccess,
                source: source
            ))
        } else {
            publisher.withdraw(id: Self.activityID)
        }
    }

    // MARK: Activity

    static func activity(
        for nowPlaying: NowPlaying,
        playerName: String,
        symbolName: String = "music.note",
        accent: ActivityAccent = .pink,
        capabilities: MediaCapabilities,
        controlAccess: MediaControlAccess,
        source: ActivitySource
    ) -> NotchActivity {
        let isPlaying = nowPlaying.state == .playing
        let canControl = controlAccess != .denied
        let subtitle = [nowPlaying.artist, nowPlaying.album]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " — ")
        let position = capabilities.contains(.progress) ? nowPlaying.position : nil

        return NotchActivity(
            id: activityID,
            source: source,
            kind: .music,
            priority: isPlaying ? .passive : pausedPriority,
            placement: isPlaying ? .notch : .commandCenter,
            title: nowPlaying.title,
            subtitle: subtitle.isEmpty ? playerName : subtitle,
            presentation: ActivityPresentation(
                symbolName: symbolName,
                accent: accent,
                compactAccessory: .symbol(isPlaying ? "waveform" : "pause.fill"),
                content: .media(MediaContent(
                    isPlaying: isPlaying,
                    position: position ?? 0,
                    positionDate: nowPlaying.positionDate,
                    // Without a position there is no progress bar to draw.
                    duration: position == nil ? nil : nowPlaying.duration,
                    artwork: capabilities.contains(.artwork) ? nowPlaying.artwork : nil,
                    artworkSymbol: symbolName,
                    trackID: nowPlaying.trackID ?? "\(nowPlaying.title)|\(nowPlaying.artist ?? "")",
                    previousActionID: canControl && capabilities.contains(.previousTrack) ? ActionID.previous : nil,
                    playPauseActionID: canControl && capabilities.contains(.playPause) ? ActionID.playPause : nil,
                    nextActionID: canControl && capabilities.contains(.nextTrack) ? ActionID.next : nil
                ))
            ),
            actions: canControl ? [] : [
                ActivityAction(id: ActionID.allowControl, title: "Allow Control…", systemImage: "lock.open"),
            ]
        )
    }
}
