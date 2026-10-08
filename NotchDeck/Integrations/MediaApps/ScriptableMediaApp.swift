import Foundation

/// How a scriptable media app exposes its artwork.
enum ArtworkSource: Sendable {
    /// A script returns the image bytes.
    case scriptData(String)
    /// The state script's last field is an image URL, fetched from one of these hosts.
    case url(allowedHosts: [String])
}

/// Everything NotchDeck needs to know about one scriptable media app (Apple Music, Spotify).
///
/// Both apps announce playback changes with a distributed notification (no permission needed)
/// and can be read and controlled with Apple Events (Automation permission). The parsing here is
/// pure, so it is unit tested without the apps.
protocol ScriptableMediaApp: Sendable {
    var id: String { get }
    var name: String { get }
    var bundleIdentifier: String { get }
    var symbolName: String { get }
    var accent: ActivityAccent { get }
    /// Distributed notification the app posts when playback changes.
    var notificationName: Notification.Name { get }
    /// What works from notifications alone, without Automation permission.
    var capabilitiesWithoutAutomation: MediaCapabilities { get }

    /// Reads the notification's user info. Nil when it carries nothing usable.
    func nowPlaying(fromNotification userInfo: [AnyHashable: Any], at date: Date) -> NowPlaying?

    /// A script returning `ScriptFields` joined by `ScriptFields.separator`, or `stopped`.
    var stateScript: String { get }
    var artworkSource: ArtworkSource { get }
    func script(for command: MediaCommand) -> String
}

/// The state script's result: `state␟title␟artist␟album␟duration␟position␟trackID[␟artworkURL]`,
/// with durations and positions in seconds.
enum ScriptFields {
    static let separator: Character = "\u{1F}"

    static func nowPlaying(from text: String, at date: Date) -> (NowPlaying, artworkURL: URL?)? {
        let fields = text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 7, let state = playbackState(fields[0]), state != .stopped else { return nil }
        let title = fields[1].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        let nowPlaying = NowPlaying(
            title: title,
            artist: nonEmpty(fields[2]),
            album: nonEmpty(fields[3]),
            state: state,
            position: number(fields[5]),
            positionDate: date,
            duration: number(fields[4]).flatMap { $0 > 0 ? $0 : nil },
            trackID: nonEmpty(fields[6]).map(normalizedTrackID)
        )
        let artworkURL = fields.count >= 8 ? nonEmpty(fields[7]).flatMap(URL.init(string:)) : nil
        return (nowPlaying, artworkURL)
    }

    /// Accepts both AppleScript (`playing`) and notification (`Playing`) spellings.
    static func playbackState(_ text: String) -> PlaybackState? {
        switch text.trimmingCharacters(in: .whitespaces).lowercased() {
        case "playing", "fast forwarding", "rewinding": .playing
        case "paused": .paused
        case "stopped": .stopped
        default: nil
        }
    }

    /// Parses a number written by AppleScript, which uses the locale's decimal separator.
    static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              text != "missing value" else { return nil }
        return text
    }

    /// Music's persistent IDs are hex in scripts but a signed integer in notifications.
    static func normalizedTrackID(_ id: String) -> String {
        id.uppercased()
    }

    /// Builds a state script that reads each property in its own `try`, so a stream or podcast
    /// missing one property still reports the rest. Never launches the app.
    static func stateScript(
        bundleIdentifier: String,
        durationExpression: String,
        idProperty: String,
        artworkURLProperty: String? = nil
    ) -> String {
        func read(_ variable: String, _ expression: String) -> String {
            """
                        set \(variable) to ""
                        try
                            set \(variable) to (\(expression)) as text
                        end try

            """
        }
        var reads = read("trackName", "name of t") + read("trackArtist", "artist of t")
            + read("trackAlbum", "album of t") + read("trackDuration", durationExpression)
            + read("trackPosition", "player position") + read("trackID", "\(idProperty) of t")
        var fields = "s & sep & trackName & sep & trackArtist & sep & trackAlbum & sep & trackDuration & sep & trackPosition & sep & trackID"
        if let artworkURLProperty {
            reads += read("trackArtwork", "\(artworkURLProperty) of t")
            fields += " & sep & trackArtwork"
        }
        return """
        if application id "\(bundleIdentifier)" is running then
            tell application id "\(bundleIdentifier)"
                with timeout of 3 seconds
                    set sep to character id 31
                    set s to (player state) as text
                    if s is "stopped" then return "stopped"
                    set t to current track
        \(reads)            return \(fields)
                end timeout
            end tell
        end if
        return "stopped"
        """
    }

    /// A command script that does nothing (and doesn't launch the app) when it isn't running.
    static func commandScript(bundleIdentifier: String, command: String) -> String {
        """
        if application id "\(bundleIdentifier)" is running then
            tell application id "\(bundleIdentifier)"
                with timeout of 3 seconds
                    \(command)
                end timeout
            end tell
        end if
        """
    }
}

// MARK: - Apple Music

struct AppleMusicApp: ScriptableMediaApp {
    let id = "appleMusic"
    let name = "Music"
    let bundleIdentifier = "com.apple.Music"
    let symbolName = "music.note"
    let accent = ActivityAccent.pink
    let notificationName = Notification.Name("com.apple.Music.playerInfo")
    /// Music's notification has no position and no artwork; both need Automation.
    let capabilitiesWithoutAutomation: MediaCapabilities = []

    func nowPlaying(fromNotification userInfo: [AnyHashable: Any], at date: Date) -> NowPlaying? {
        guard let stateText = userInfo["Player State"] as? String,
              let state = ScriptFields.playbackState(stateText), state != .stopped else { return nil }
        // Radio streams report the song as "Stream Title" and the station as "Name".
        let title = ScriptFields.nonEmpty(userInfo["Name"] as? String)
            ?? ScriptFields.nonEmpty(userInfo["Stream Title"] as? String)
        guard let title else { return nil }
        let totalTime = (userInfo["Total Time"] as? NSNumber)?.doubleValue
        let persistentID = (userInfo["PersistentID"] as? NSNumber).map { Self.hexID($0.int64Value) }
        return NowPlaying(
            title: title,
            artist: ScriptFields.nonEmpty(userInfo["Artist"] as? String),
            album: ScriptFields.nonEmpty(userInfo["Album"] as? String),
            state: state,
            positionDate: date,
            duration: totalTime.flatMap { $0 > 0 ? $0 / 1000 : nil },
            trackID: persistentID
        )
    }

    /// The notification's signed persistent ID as the 16-digit hex string scripts return.
    static func hexID(_ value: Int64) -> String {
        let hex = String(UInt64(bitPattern: value), radix: 16, uppercase: true)
        return String(repeating: "0", count: max(16 - hex.count, 0)) + hex
    }

    var stateScript: String {
        ScriptFields.stateScript(bundleIdentifier: bundleIdentifier, durationExpression: "duration of t", idProperty: "persistent ID")
    }

    var artworkSource: ArtworkSource {
        .scriptData("""
        if application id "\(bundleIdentifier)" is running then
            tell application id "\(bundleIdentifier)"
                with timeout of 3 seconds
                    try
                        return raw data of artwork 1 of current track
                    end try
                end timeout
            end tell
        end if
        return ""
        """)
    }

    func script(for command: MediaCommand) -> String {
        let verb = switch command {
        case .playPause: "playpause"
        case .nextTrack: "next track"
        // Like the previous-track key: restarts the song unless it just began.
        case .previousTrack: "back track"
        }
        return ScriptFields.commandScript(bundleIdentifier: bundleIdentifier, command: verb)
    }
}

// MARK: - Spotify

struct SpotifyApp: ScriptableMediaApp {
    let id = "spotify"
    let name = "Spotify"
    let bundleIdentifier = "com.spotify.client"
    let symbolName = "music.note"
    let accent = ActivityAccent.green
    let notificationName = Notification.Name("com.spotify.client.PlaybackStateChanged")
    /// Spotify's notification includes the position; artwork needs a script.
    let capabilitiesWithoutAutomation: MediaCapabilities = [.progress]

    func nowPlaying(fromNotification userInfo: [AnyHashable: Any], at date: Date) -> NowPlaying? {
        guard let stateText = userInfo["Player State"] as? String,
              let state = ScriptFields.playbackState(stateText), state != .stopped,
              let title = ScriptFields.nonEmpty(userInfo["Name"] as? String) else { return nil }
        let duration = (userInfo["Duration"] as? NSNumber)?.doubleValue
        return NowPlaying(
            title: title,
            artist: ScriptFields.nonEmpty(userInfo["Artist"] as? String),
            album: ScriptFields.nonEmpty(userInfo["Album"] as? String),
            state: state,
            position: (userInfo["Playback Position"] as? NSNumber)?.doubleValue,
            positionDate: date,
            duration: duration.flatMap { $0 > 0 ? $0 / 1000 : nil },
            trackID: ScriptFields.nonEmpty(userInfo["Track ID"] as? String).map(ScriptFields.normalizedTrackID)
        )
    }

    var stateScript: String {
        ScriptFields.stateScript(
            bundleIdentifier: bundleIdentifier,
            durationExpression: "(duration of t) / 1000",
            idProperty: "id",
            artworkURLProperty: "artwork url"
        )
    }

    var artworkSource: ArtworkSource {
        .url(allowedHosts: ["scdn.co", "spotifycdn.com"])
    }

    func script(for command: MediaCommand) -> String {
        let verb = switch command {
        case .playPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        }
        return ScriptFields.commandScript(bundleIdentifier: bundleIdentifier, command: verb)
    }
}
