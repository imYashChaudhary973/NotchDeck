import Foundation

enum PlaybackState: Equatable, Sendable {
    case playing
    case paused
    case stopped
}

/// What a media app is playing, as far as that app reports it.
struct NowPlaying: Equatable, Sendable {
    var title: String
    var artist: String?
    var album: String?
    var state: PlaybackState
    /// Playback position at `positionDate`. Nil when the app doesn't report it.
    var position: TimeInterval?
    var positionDate: Date
    var duration: TimeInterval?
    /// Encoded artwork image (PNG/JPEG), already scaled down for the notch.
    var artwork: Data?
    /// Identifies the track, so a change of track can be told apart from a change of state.
    var trackID: String?

    init(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        state: PlaybackState,
        position: TimeInterval? = nil,
        positionDate: Date = .now,
        duration: TimeInterval? = nil,
        artwork: Data? = nil,
        trackID: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.state = state
        self.position = position
        self.positionDate = positionDate
        self.duration = duration
        self.artwork = artwork
        self.trackID = trackID
    }

    /// The playback position at `date`, extrapolated while playing.
    func position(at date: Date) -> TimeInterval? {
        guard let position else { return nil }
        let elapsed = state == .playing ? max(date.timeIntervalSince(positionDate), 0) : 0
        let value = max(position + elapsed, 0)
        return duration.map { min(value, $0) } ?? value
    }

    /// Whether `other` is the same track (by ID when both have one, otherwise by metadata).
    func isSameTrack(as other: NowPlaying) -> Bool {
        if let trackID, let otherID = other.trackID { return trackID == otherID }
        return title == other.title && artist == other.artist && album == other.album
    }
}

/// What a media provider can currently do. Anything missing is hidden in the notch.
struct MediaCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let artwork = MediaCapabilities(rawValue: 1 << 0)
    static let progress = MediaCapabilities(rawValue: 1 << 1)
    static let playPause = MediaCapabilities(rawValue: 1 << 2)
    static let nextTrack = MediaCapabilities(rawValue: 1 << 3)
    static let previousTrack = MediaCapabilities(rawValue: 1 << 4)

    static let controls: MediaCapabilities = [.playPause, .nextTrack, .previousTrack]
    static let all: MediaCapabilities = [.artwork, .progress, .controls]
}

enum MediaCommand: Sendable {
    case playPause
    case nextTrack
    case previousTrack
}

/// Whether NotchDeck may control the media app (macOS Automation permission).
enum MediaControlAccess: Equatable, Sendable {
    /// Not asked yet. The first control the user presses asks.
    case undetermined
    case granted
    /// The user said no; controls stay hidden until it is allowed in System Settings.
    case denied
}

/// One media app (Apple Music, Spotify…) as a source of Now Playing information and controls.
///
/// The music feature talks only to this protocol, so no part of the app depends on a specific
/// service. Implementations use supported mechanisms only, and report what they can't do through
/// `capabilities` instead of failing.
@MainActor
protocol MediaProvider: AnyObject {
    /// Stable identifier, for example `appleMusic`.
    var id: String { get }
    /// User-facing name, for example "Music".
    var name: String { get }
    var symbolName: String { get }
    var accent: ActivityAccent { get }

    /// What the app is playing; nil when it is not running or has nothing loaded.
    var nowPlaying: NowPlaying? { get }
    var capabilities: MediaCapabilities { get }
    var controlAccess: MediaControlAccess { get }

    /// Calls back (on the main actor) whenever `nowPlaying`, `capabilities` or `controlAccess` change.
    func startObserving(onChange: @escaping @MainActor () -> Void)
    func stopObserving()
    func send(_ command: MediaCommand)
    /// Re-reads state that the app doesn't announce (such as the position after a seek), if supported.
    func refresh()
}
