# 0006. Media and Calendar Providers

- Status: Accepted
- Date: 2026-10-08

## Context

Phase 3 adds Now Playing (Apple Music, Spotify) and Calendar (EventKit). It also needs context resolution: a meeting that is about to start must interrupt music, and music must return afterwards.

Constraints:

1. **No private APIs.** System-wide Now Playing (`MediaRemote.framework`) is private and has been restricted for third-party apps. The rest of the app must not depend on one music service.
2. **Contextual permission.** Calendar access may be asked for only when the user turns the feature on. Controlling another app needs the Automation permission.
3. **Event-driven.** "Do not continuously query EventKit unnecessarily", and idle cost must stay at zero.

## Decision

### Music

- **`MediaProvider` protocol** (`Features/Music/`): one media app as a source of `NowPlaying` (title, artist, album, state, position, duration, artwork, track ID) and `MediaCommand`s. It reports what it can currently do as `MediaCapabilities` (`artwork`, `progress`, `playPause`, `nextTrack`, `previousTrack`) and whether it may be controlled (`MediaControlAccess`). The notch hides anything that is unsupported.
- **`MusicProvider`** (the `ActivityProvider`, source `music`) combines any number of media providers. It shows the player that most recently started playing, otherwise the one most recently paused. Playing music is a Passive (20) `.notch` Live Activity. Paused music is `.commandCenter` (priority 22, above Quick Actions), so pausing from the featured card keeps the card and paused music never holds the notch. Stopped or quit means withdrawn.
- **`ScriptableMediaProvider`** (`Integrations/MediaApps/`) implements `MediaProvider` for scriptable apps, described by a `ScriptableMediaApp` (`AppleMusicApp`, `SpotifyApp`):
  - **Distributed notifications** (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`) report every playback change. They need no permission and no polling. They are observed with `.deliverImmediately`, because an accessory app is almost never active.
  - **Apple Events** (AppleScript via `NSAppleScript`, on a background queue with a 3 s script timeout) read the position and artwork and send play/pause/next/previous. The Automation prompt appears the first time the user presses a control. If the user denies it, the controls are replaced by an "Allow Control…" button that opens System Settings ▸ Privacy & Security ▸ Automation. On launch, permission is checked with `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false)`, so it never prompts.
  - Every script starts with `if application id "…" is running`, and scripts are sent only while the app runs, so NotchDeck never launches a media app.
  - Artwork is scaled to 192 px off the main thread. Music returns the image bytes. Spotify returns a URL, which is fetched only over HTTPS from Spotify's image CDN (`scdn.co`, `spotifycdn.com`) with an ephemeral session.
  - Players don't announce seeks, so the position is re-read when the Now Playing activity comes on screen (`displayedActivitiesChanged`).
- The hardened runtime needs the `com.apple.security.automation.apple-events` entitlement and `NSAppleEventsUsageDescription`.

### Calendar

- **`CalendarStore` protocol** with `EventKitCalendarStore` (read-only): authorization, `requestAccess()` (`requestFullAccessToEvents`), calendars, events in a range excluding chosen calendars (cancelled and declined events are dropped), and change observation (`EKEventStoreChanged`, clock change, day change, wake).
- **`CalendarProvider`** (source `calendar`) publishes:
  - **The notch meeting**: the soonest event a rule applies to. It has Join (when a meeting link was found) and Dismiss. It expires when its notch time ends, even if no wake-up runs.
  - **The schedule** (`.commandCenter`, new `ActivityContent.schedule`): events in progress or starting within the look-ahead, with Join buttons.
  - **An access row** (`.commandCenter`) while access isn't granted: Allow Access… (not determined) or Open Settings… (denied, restricted, write-only).
- **`CalendarRules`** (pure): ordered `MeetingRule`s (lead time → priority). Defaults are within 15 min Active (30), within 5 min Time Sensitive (40) and from 1 min before Attention Required (50, auto-peek), then a 5 min "Starting now" grace capped at the event's end. The notch lead time (5/10/15/30 min) and look-ahead (3/6/12/24 h) are settings. All-day events are listed but never take the notch.
- **Refresh scheduling**: EventKit is queried on start, on store/clock/day/wake changes and every 6 h. Each query reaches look-ahead + 6 h, so events entering the window are already cached. Between queries the provider wakes once, at the next rule boundary, start or end of a cached event. It also wakes once a minute while a countdown ("12m") is on the notch. It never ticks every second.
- **Meeting links** (`MeetingLinkDetector`): the event URL, then location, then notes are searched for known services (Zoom, Google Meet, Teams, Webex, FaceTime, Chime, Jitsi, Whereby, GoTo, BlueJeans, Slack huddles). A location that is only a web link also counts. Only `https`/`http` links are opened.
- **Permission timing**: the feature is off by default. `AppEnvironment` calls `requestAccess()` only when the user turns Calendar on in Settings. Registering at launch (feature already on) never prompts. `NSCalendarsFullAccessUsageDescription` explains the request.

### Context resolution

No resolver change was needed: priorities and the existing rules decide. Music (20) loses to a meeting within 15 min (30). The meeting escalates to 40, then to 50, and the attention peek fires once. When the meeting leaves the notch (grace over, joined or dismissed), music is primary again, because interrupted activities stay in the store. A running timer (30) keeps the notch against an equal-priority upcoming meeting (incumbent rule) until the meeting reaches 40. `ContextResolutionTests` cover this with the real providers and fakes for the apps and EventKit.

## Alternatives Considered

- **MediaRemote / `MRMediaRemoteGetNowPlayingInfo`.** It would show any app's playback, but it is a private framework and is already restricted. Ruled out by the private API rule.
- **Polling the apps with AppleScript.** Simple, but it wakes the CPU all day and needs Automation permission just to *display* the track. Notifications are free.
- **ScriptingBridge.** The same Apple Events with generated headers or untyped `value(forKey:)`. It adds nothing over short AppleScript sources, and its objects aren't safe to share across threads.
- **Asking for calendar access at launch or when the provider starts.** Simpler, but it breaks the contextual-permission principle.
- **A `.countdown` accessory for meetings.** It ticks every second (about 1% CPU, [ADR 0005](0005-local-utility-providers.md)) for a value that only needs minute precision.
- **Re-querying EventKit at every boundary.** Correct, but redundant: the cached window already contains the events.

## Consequences

- Only Apple Music and Spotify are shown. Browsers, podcasts and other players are not, until they offer a supported integration. A new player is one `ScriptableMediaApp` (or another `MediaProvider`) added in `AppEnvironment`.
- Without Automation permission: Music shows the track and controls but no artwork or progress; Spotify shows the track, progress and controls but no artwork. After a denial, both show the track and an Allow Control button.
- What is already playing at launch is shown only if Automation was granted earlier. Otherwise it appears with the next playback change.
- Idle cost is unchanged: with Music, Spotify observers and Calendar registered, 0.0% CPU and 0 idle wake-ups. Music on the notch costs nothing extra; the progress bar ticks once a second only while the command center is open.
- Spotify artwork means a network request to Spotify's CDN (documented in `PRIVACY.md`). Calendar data is never stored. Only excluded calendar IDs are kept in `UserDefaults`.
- New content style `schedule` and a sample with artwork were added to the warm-up samples. `NotchPrewarmerTests` enforces this.
