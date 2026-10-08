import Foundation
import Testing
@testable import NotchDeck

@MainActor
final class FakeMediaProvider: MediaProvider {
    let id: String
    let name: String
    let symbolName = "music.note"
    let accent: ActivityAccent
    var nowPlaying: NowPlaying?
    var capabilities: MediaCapabilities = .all
    var controlAccess: MediaControlAccess = .granted
    private(set) var sent: [MediaCommand] = []
    private(set) var refreshCount = 0
    private(set) var isObserving = false
    private var onChange: (@MainActor () -> Void)?

    init(id: String, name: String? = nil, accent: ActivityAccent = .pink) {
        self.id = id
        self.name = name ?? id
        self.accent = accent
    }

    func startObserving(onChange: @escaping @MainActor () -> Void) {
        isObserving = true
        self.onChange = onChange
    }

    func stopObserving() {
        isObserving = false
        onChange = nil
    }

    func send(_ command: MediaCommand) { sent.append(command) }
    func refresh() { refreshCount += 1 }

    /// Simulates the app announcing a change.
    func update(_ change: (FakeMediaProvider) -> Void) {
        change(self)
        onChange?()
    }
}

@MainActor
struct MusicProviderTests {
    let engine = ActivityEngine(schedulesExpiry: false)
    let clock = TestClock()
    let key = ActivityKey(source: ActivitySource(rawValue: "music"), id: MusicProvider.activityID)

    static func track(_ title: String, _ state: PlaybackState = .playing, id: String? = nil) -> NowPlaying {
        NowPlaying(title: title, artist: "Artist", album: "Album", state: state, position: 30,
                   positionDate: Date(timeIntervalSinceReferenceDate: 1_000), duration: 200,
                   artwork: Data([1, 2, 3]), trackID: id ?? title)
    }

    private func makeProvider(_ players: [FakeMediaProvider], workspace: FakeWorkspace = FakeWorkspace()) -> MusicProvider {
        MusicProvider(players: players, workspace: workspace, now: { [clock] in clock.now })
    }

    private var media: MediaContent? {
        guard case .media(let media) = engine.activity(for: key)?.presentation.content else { return nil }
        return media
    }

    @Test func nothingPlayingMeansNoActivity() {
        let player = FakeMediaProvider(id: "music")
        engine.register(makeProvider([player]))

        #expect(engine.activity(for: key) == nil)
        #expect(player.isObserving)
    }

    @Test func playingMusicIsAPassiveLiveActivity() throws {
        let player = FakeMediaProvider(id: "music", name: "Music")
        player.nowPlaying = Self.track("Midnight City")
        engine.register(makeProvider([player]))

        let activity = try #require(engine.resolution.primary)
        #expect(activity.key == key)
        #expect(activity.kind == .music)
        #expect(activity.priority == .passive)
        #expect(activity.placement == .notch)
        #expect(activity.title == "Midnight City")
        #expect(activity.subtitle == "Artist — Album")
        #expect(activity.presentation.compactAccessory == .symbol("waveform"))
        #expect(media?.isPlaying == true)
        #expect(media?.position == 30)
        #expect(media?.duration == 200)
        #expect(media?.artwork == Data([1, 2, 3]))
        #expect(media?.trackID == "Midnight City")
        #expect(media?.playPauseActionID == MusicProvider.ActionID.playPause)
        #expect(media?.nextActionID == MusicProvider.ActionID.next)
        #expect(media?.previousActionID == MusicProvider.ActionID.previous)
    }

    @Test func pausedMusicMovesToTheCommandCenter() {
        let player = FakeMediaProvider(id: "music")
        player.nowPlaying = Self.track("Song")
        engine.register(makeProvider([player]))

        player.update { $0.nowPlaying?.state = .paused }

        #expect(engine.resolution.primary == nil)
        #expect(engine.activity(for: key)?.placement == .commandCenter)
        #expect(engine.activity(for: key)?.presentation.compactAccessory == .symbol("pause.fill"))
        #expect(media?.isPlaying == false)
    }

    @Test func stoppingOrQuittingWithdrawsTheActivity() {
        let player = FakeMediaProvider(id: "music")
        player.nowPlaying = Self.track("Song")
        engine.register(makeProvider([player]))

        player.update { $0.nowPlaying = nil }

        #expect(engine.activity(for: key) == nil)
    }

    @Test func theMostRecentlyStartedPlayerIsShown() {
        let music = FakeMediaProvider(id: "music")
        let spotify = FakeMediaProvider(id: "spotify")
        music.nowPlaying = Self.track("From Music")
        let provider = makeProvider([music, spotify])
        engine.register(provider)

        clock.advance(by: 10)
        spotify.update { $0.nowPlaying = Self.track("From Spotify") }
        #expect(engine.activity(for: key)?.title == "From Spotify")
        #expect(provider.activePlayerID == "spotify")

        // Spotify pauses: Music is still playing, so it is shown.
        clock.advance(by: 10)
        spotify.update { $0.nowPlaying?.state = .paused }
        #expect(engine.activity(for: key)?.title == "From Music")

        // Music stops too: the paused Spotify track remains in the command center.
        music.update { $0.nowPlaying = nil }
        #expect(engine.activity(for: key)?.title == "From Spotify")
        #expect(engine.activity(for: key)?.placement == .commandCenter)
    }

    @Test func activePlayerSelectionPrefersPlayingThenRecentlyPaused() {
        let early = Date(timeIntervalSinceReferenceDate: 1)
        let late = Date(timeIntervalSinceReferenceDate: 2)

        #expect(MusicProvider.activePlayerID(
            states: [("a", .playing), ("b", .playing)], lastPlayed: ["a": early, "b": late], lastPaused: [:]
        ) == "b")
        #expect(MusicProvider.activePlayerID(
            states: [("a", .paused), ("b", .playing)], lastPlayed: ["b": early], lastPaused: ["a": late]
        ) == "b")
        #expect(MusicProvider.activePlayerID(
            states: [("a", .paused), ("b", .paused)], lastPlayed: [:], lastPaused: ["a": late, "b": early]
        ) == "a")
        #expect(MusicProvider.activePlayerID(
            states: [("a", .stopped), ("b", nil)], lastPlayed: [:], lastPaused: [:]
        ) == nil)
    }

    @Test func transportButtonsAreRoutedToTheActivePlayer() {
        let music = FakeMediaProvider(id: "music")
        let spotify = FakeMediaProvider(id: "spotify")
        music.nowPlaying = Self.track("Song")
        engine.register(makeProvider([music, spotify]))

        engine.perform(actionID: MusicProvider.ActionID.playPause, on: key)
        engine.perform(actionID: MusicProvider.ActionID.next, on: key)
        engine.perform(actionID: MusicProvider.ActionID.previous, on: key)

        #expect(music.sent == [.playPause, .nextTrack, .previousTrack])
        #expect(spotify.sent.isEmpty)
    }

    @Test func unsupportedCapabilitiesAreHidden() {
        let player = FakeMediaProvider(id: "music")
        player.nowPlaying = Self.track("Song")
        player.capabilities = [.playPause]
        engine.register(makeProvider([player]))

        #expect(media?.playPauseActionID == MusicProvider.ActionID.playPause)
        #expect(media?.nextActionID == nil)
        #expect(media?.previousActionID == nil)
        #expect(media?.artwork == nil)
        // Without a position there is no progress bar.
        #expect(media?.duration == nil)
    }

    @Test func deniedControlHidesTransportAndOffersSettings() {
        let workspace = FakeWorkspace()
        let player = FakeMediaProvider(id: "music")
        player.nowPlaying = Self.track("Song")
        player.controlAccess = .denied
        player.capabilities = []
        engine.register(makeProvider([player], workspace: workspace))

        #expect(media?.playPauseActionID == nil)
        #expect(engine.activity(for: key)?.actions.map(\.id) == [MusicProvider.ActionID.allowControl])

        engine.perform(actionID: MusicProvider.ActionID.allowControl, on: key)
        #expect(workspace.opened == [MusicProvider.automationSettingsURL])
    }

    @Test func undeterminedControlStillOffersButtons() {
        let player = FakeMediaProvider(id: "music")
        player.nowPlaying = Self.track("Song")
        player.controlAccess = .undetermined
        player.capabilities = .controls
        engine.register(makeProvider([player]))

        #expect(media?.playPauseActionID != nil)
        #expect(engine.activity(for: key)?.actions.isEmpty == true)
    }

    @Test func comingIntoViewResynchronizesThePosition() {
        let player = FakeMediaProvider(id: "music")
        player.nowPlaying = Self.track("Song")
        engine.register(makeProvider([player]))

        engine.updateDisplayedActivities([key])
        engine.updateDisplayedActivities([key])
        #expect(player.refreshCount == 1)

        engine.updateDisplayedActivities([])
        engine.updateDisplayedActivities([key])
        #expect(player.refreshCount == 2)
    }

    @Test func stoppingStopsObservingPlayers() {
        let player = FakeMediaProvider(id: "music")
        player.nowPlaying = Self.track("Song")
        let provider = makeProvider([player])
        engine.register(provider)

        engine.unregister(provider.source)

        #expect(!player.isObserving)
        #expect(engine.activity(for: key) == nil)
    }
}
