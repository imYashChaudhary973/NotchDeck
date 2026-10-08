# Privacy Principles

This document describes the privacy principles NotchDeck is designed and built around. It is an engineering commitment for contributors, not a legal policy.

## Sensitive Systems

NotchDeck is planned to touch several kinds of sensitive local information:

| System | Examples of sensitive data |
| --- | --- |
| **Calendar** | Meeting titles, attendees, locations, video-call links |
| **Clipboard** | Anything a user copies — including passwords, tokens and personal messages |
| **Files** | Filenames, paths and file contents placed on the shelf |
| **Developer activity** | Project paths, repository names, prompts, tool output from Claude Code / Codex / other tools |
| **System information** | Running applications, CPU / memory usage, audio devices |

All of it is treated as private by default.

## Principles

1. **Local by default.** Data NotchDeck reads stays on the user's Mac. Nothing is sent off-device unless a feature explicitly requires it and the user understands that.
2. **Contextual permissions.** Permissions (e.g. Calendar access) are requested only when the user enables the feature that needs them — never all at once on first launch — with a clear explanation of why.
3. **Clipboard history stays local.** Clipboard history, when enabled, is stored only on the device, is user-clearable, and is never synced or uploaded by default. Clipboard contents are never written to logs.
4. **Developer activity stays local.** Activity from developer tools is received over a local channel and is not forwarded elsewhere.
5. **Credentials in the Keychain.** Any credentials or tokens NotchDeck ever needs are stored through appropriate system mechanisms such as the Keychain — never in plain-text preferences, files or logs.
6. **Minimal retention.** Keep data only as long as the feature needs it, and give users controls to clear it.
7. **No unnecessary telemetry.** NotchDeck does not collect analytics or usage tracking it doesn't need. If diagnostic reporting is ever proposed, it must be opt-in and documented here first.
8. **Careful logging.** Logs must not contain clipboard contents, calendar details, file contents, or sensitive filenames/paths. Use `os.Logger` privacy annotations (`privacy: .private`) for any dynamic value that could be sensitive.

## What NotchDeck Stores Today

| Data | Where | Why |
| --- | --- | --- |
| Settings | `UserDefaults` | Preferences |
| Timers (duration, end time, the optional name you type) | `UserDefaults` (`timers.saved`) | Running timers survive a relaunch. Removed when they finish or are cancelled, and when Timers is turned off. |
| Keep Awake session (on/off, end time) | `UserDefaults` (`keepAwake.session`) | An active session survives a relaunch |
| Calendars you turned off (calendar IDs only), look-ahead and notch timing | `UserDefaults` (`calendar.*`) | Calendar settings |

CPU, memory, battery and audio-device information is read on demand, shown in the notch and never stored, logged or sent anywhere.

### Calendar

- Read-only access through EventKit, requested only when you turn Calendar on in Settings (or press Allow Access…). Turning the feature off stops all reading; the permission itself is managed in System Settings ▸ Privacy & Security ▸ Calendars.
- Event titles, times and video-call links are kept in memory while shown and never stored, logged or sent anywhere. Event notes and locations are scanned in memory only to find a meeting link.
- Join opens only `https`/`http` links to known meeting services (or a location that is just a web link), in your default browser or meeting app.

### Now Playing

- Track information comes from notifications Music and Spotify broadcast on the Mac. Reading it needs no permission and nothing is stored.
- Playback controls, the position and artwork use Apple Events and need your Automation permission, which macOS asks for the first time you press a control. NotchDeck never launches Music or Spotify.
- **Network:** Spotify provides artwork as a link. NotchDeck downloads it over HTTPS, only from Spotify's image servers (`scdn.co`, `spotifycdn.com`), without cookies or a cache (ephemeral session). It is the only network request NotchDeck makes, and it sends nothing about you beyond the image request itself. Music artwork comes from the Music app directly.

## For Contributors

Any change that reads a new category of user data, adds a permission, stores user data, or communicates off-device must update this document in the same change.
