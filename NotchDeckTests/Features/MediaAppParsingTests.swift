import AppKit
import Testing
@testable import NotchDeck

struct MediaAppParsingTests {
    let date = Date(timeIntervalSinceReferenceDate: 5_000)
    let separator = String(ScriptFields.separator)

    // MARK: Notifications

    @Test func parsesAppleMusicNotifications() throws {
        let info: [AnyHashable: Any] = [
            "Name": "Midnight City",
            "Artist": "M83",
            "Album": "Hurry Up, We're Dreaming",
            "Player State": "Playing",
            "Total Time": NSNumber(value: 243_000),
            "PersistentID": NSNumber(value: Int64(-6_942_364_521_234_567)),
        ]

        let nowPlaying = try #require(AppleMusicApp().nowPlaying(fromNotification: info, at: date))

        #expect(nowPlaying.title == "Midnight City")
        #expect(nowPlaying.artist == "M83")
        #expect(nowPlaying.album == "Hurry Up, We're Dreaming")
        #expect(nowPlaying.state == .playing)
        #expect(nowPlaying.duration == 243)
        // Music's notification has no position.
        #expect(nowPlaying.position == nil)
        #expect(nowPlaying.trackID == AppleMusicApp.hexID(-6_942_364_521_234_567))
        #expect(nowPlaying.trackID?.count == 16)
    }

    @Test func appleMusicPersistentIDsMatchTheScriptFormat() {
        #expect(AppleMusicApp.hexID(255) == "00000000000000FF")
        #expect(AppleMusicApp.hexID(-1) == "FFFFFFFFFFFFFFFF")
    }

    @Test func appleMusicRadioUsesTheStreamTitle() {
        let info: [AnyHashable: Any] = ["Player State": "Playing", "Stream Title": "Live Set"]
        #expect(AppleMusicApp().nowPlaying(fromNotification: info, at: date)?.title == "Live Set")
    }

    @Test func stoppedOrEmptyNotificationsMeanNothingIsPlaying() {
        #expect(AppleMusicApp().nowPlaying(fromNotification: ["Player State": "Stopped", "Name": "Song"], at: date) == nil)
        #expect(AppleMusicApp().nowPlaying(fromNotification: ["Player State": "Paused"], at: date) == nil)
        #expect(SpotifyApp().nowPlaying(fromNotification: [:], at: date) == nil)
    }

    @Test func parsesSpotifyNotificationsWithPosition() throws {
        let info: [AnyHashable: Any] = [
            "Name": "Instant Crush",
            "Artist": "Daft Punk",
            "Album": "Random Access Memories",
            "Player State": "Paused",
            "Duration": NSNumber(value: 337_000),
            "Playback Position": NSNumber(value: 12.5),
            "Track ID": "spotify:track:2cGxRwrMyEAp8dEbuZaVv6",
        ]

        let nowPlaying = try #require(SpotifyApp().nowPlaying(fromNotification: info, at: date))

        #expect(nowPlaying.state == .paused)
        #expect(nowPlaying.duration == 337)
        #expect(nowPlaying.position == 12.5)
        #expect(nowPlaying.positionDate == date)
        #expect(nowPlaying.trackID == "SPOTIFY:TRACK:2CGXRWRMYEAP8DEBUZAVV6")
    }

    @Test func spotifyReportsProgressWithoutAutomationButMusicDoesNot() {
        #expect(SpotifyApp().capabilitiesWithoutAutomation.contains(.progress))
        #expect(AppleMusicApp().capabilitiesWithoutAutomation.isEmpty)
    }

    // MARK: Script results

    @Test func parsesStateScriptResults() throws {
        let text = ["playing", "Song", "Artist", "", "200,5", "42.25", "abc123"].joined(separator: separator)

        let (nowPlaying, artworkURL) = try #require(ScriptFields.nowPlaying(from: text, at: date))

        #expect(nowPlaying.title == "Song")
        #expect(nowPlaying.album == nil)
        // Locales with a decimal comma are handled.
        #expect(nowPlaying.duration == 200.5)
        #expect(nowPlaying.position == 42.25)
        #expect(nowPlaying.trackID == "ABC123")
        #expect(artworkURL == nil)
    }

    @Test func parsesTheArtworkURLField() throws {
        let text = ["paused", "Song", "", "", "100", "1", "id", "https://i.scdn.co/image/ab67"].joined(separator: separator)
        let (nowPlaying, artworkURL) = try #require(ScriptFields.nowPlaying(from: text, at: date))
        #expect(nowPlaying.state == .paused)
        #expect(artworkURL == URL(string: "https://i.scdn.co/image/ab67"))
    }

    @Test func rejectsStoppedAndMalformedScriptResults() {
        #expect(ScriptFields.nowPlaying(from: "stopped", at: date) == nil)
        #expect(ScriptFields.nowPlaying(from: "playing\u{1F}Song", at: date) == nil)
        #expect(ScriptFields.nowPlaying(from: ["playing", " ", "", "", "", "", ""].joined(separator: separator), at: date) == nil)
        #expect(ScriptFields.nowPlaying(from: ["buffering", "Song", "", "", "", "", ""].joined(separator: separator), at: date) == nil)
    }

    @Test func missingValuesAreTreatedAsAbsent() {
        #expect(ScriptFields.nonEmpty("missing value") == nil)
        #expect(ScriptFields.nonEmpty("  ") == nil)
        #expect(ScriptFields.nonEmpty("M83") == "M83")
    }

    @Test func fastForwardingCountsAsPlaying() {
        #expect(ScriptFields.playbackState("fast forwarding") == .playing)
        #expect(ScriptFields.playbackState("Playing") == .playing)
    }

    // MARK: Safety

    @Test func scriptsNeverLaunchTheApp() {
        for app in [AppleMusicApp(), SpotifyApp()] as [any ScriptableMediaApp] {
            let guardLine = "if application id \"\(app.bundleIdentifier)\" is running then"
            #expect(app.stateScript.hasPrefix(guardLine))
            for command in [MediaCommand.playPause, .nextTrack, .previousTrack] {
                #expect(app.script(for: command).hasPrefix(guardLine))
            }
            if case .scriptData(let script) = app.artworkSource {
                #expect(script.hasPrefix(guardLine))
            }
        }
    }

    @Test func artworkIsOnlyDownloadedFromTheAppsCDNOverHTTPS() {
        let hosts = ["scdn.co"]
        #expect(ArtworkLoader.isAllowed(URL(string: "https://i.scdn.co/image/x")!, hosts: hosts))
        #expect(ArtworkLoader.isAllowed(URL(string: "https://scdn.co/x")!, hosts: hosts))
        #expect(!ArtworkLoader.isAllowed(URL(string: "http://i.scdn.co/image/x")!, hosts: hosts))
        #expect(!ArtworkLoader.isAllowed(URL(string: "https://evilscdn.co/x")!, hosts: hosts))
        #expect(!ArtworkLoader.isAllowed(URL(string: "file:///etc/passwd")!, hosts: hosts))
    }

    @Test func artworkIsScaledDown() throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))

        let thumbnail = try #require(ArtworkLoader.makeThumbnail(from: data))
        let image = try #require(NSBitmapImageRep(data: thumbnail))

        #expect(image.pixelsWide == ArtworkLoader.maxPixelSize)
        #expect(ArtworkLoader.makeThumbnail(from: Data("not an image".utf8)) == nil)
    }

    // MARK: Now Playing

    @Test func positionIsExtrapolatedOnlyWhilePlaying() {
        var nowPlaying = NowPlaying(title: "Song", state: .playing, position: 10, positionDate: date, duration: 30)
        #expect(nowPlaying.position(at: date.addingTimeInterval(5)) == 15)
        #expect(nowPlaying.position(at: date.addingTimeInterval(500)) == 30)
        nowPlaying.state = .paused
        #expect(nowPlaying.position(at: date.addingTimeInterval(5)) == 10)
        nowPlaying.position = nil
        #expect(nowPlaying.position(at: date) == nil)
    }

    @Test func tracksAreComparedByIDWhenAvailable() {
        let a = NowPlaying(title: "Song", artist: "A", state: .playing, trackID: "1")
        var b = a
        b.state = .paused
        #expect(a.isSameTrack(as: b))
        b.trackID = "2"
        #expect(!a.isSameTrack(as: b))
        var c = a
        c.trackID = nil
        #expect(a.isSameTrack(as: c))
    }
}
