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
| Shelf items: bookmarks to dropped files and folders (with their path and name), dropped links and text, when each item expires | `~/Library/Application Support/NotchDeck/Shelf/shelf.json` (readable only by you) | Items stay on the shelf across a relaunch until they expire. Removed with the item; everything is removed when the shelf is turned off. |
| Files the shelf received without a file of their own (a photo dragged from Photos, a mail attachment, a dragged image) | `~/Library/Application Support/NotchDeck/Shelf/Items/` | Deleted when the item is removed or expires |
| Clipboard history (only when turned on): copied text (with formatting for small copies), links, colors, file paths, images, the time and the app name | `~/Library/Application Support/NotchDeck/Clipboard/` (`history.json`, `Images/`; readable only by you) | So copies can be found and copied again. Limited by count (default 50) and age (default 7 days) unless pinned. Clearable in Settings, even while the feature is off. |
| Apps excluded from clipboard history (bundle IDs) | `UserDefaults` (`clipboard.*`) | Clipboard settings |
| The developer bridge socket (holds no data) | `~/Library/Application Support/NotchDeck/Bridge/bridge.sock` (reachable only by you) | Developer tools report sessions through it. Removed when Developer agents is turned off. |

CPU, memory, battery and audio-device information is read on demand, shown in the notch and never stored, logged or sent anywhere. Developer agent sessions are kept in memory only (see below).

### Calendar

- Read-only access through EventKit, requested only when you turn Calendar on in Settings (or press Allow Access…). Turning the feature off stops all reading; the permission itself is managed in System Settings ▸ Privacy & Security ▸ Calendars.
- Event titles, times and video-call links are kept in memory while shown and never stored, logged or sent anywhere. Event notes and locations are scanned in memory only to find a meeting link.
- Join opens only `https`/`http` links to known meeting services (or a location that is just a web link), in your default browser or meeting app.

### File Shelf

- Dropped files and folders are referenced (bookmarks), never copied or read. NotchDeck makes a small Quick Look thumbnail for display; it is kept in memory only.
- Only `http`/`https` links are kept or opened. Nothing on the shelf is sent anywhere, except where you explicitly use Share or AirDrop.
- Watching for drags uses a mouse-event monitor that sees only button presses and pointer movement (never keystrokes) and needs no permission. It reads only the types of a drag, not its contents, until you drop.

### Clipboard history

- **Off by default.** Nothing is read until you turn it on in Settings.
- While on, NotchDeck checks once a second whether the clipboard changed, using a counter that reveals nothing about the contents. Contents are read only after a change.
- Never kept: content apps mark as concealed or transient (passwords, one-time codes), anything copied while a password manager (1Password, Passwords, Keychain Access, Bitwarden and others) is frontmost, copies from apps you exclude, and what was on the clipboard before you turned the feature on. Pause stops keeping copies.
- On macOS 15.4 and later, macOS may ask once whether NotchDeck may paste from other apps, right after you turn the feature on. If you choose to be asked every time, or deny it, NotchDeck stops reading and shows a link to Privacy & Security instead.
- Clipboard contents are never logged, synced, uploaded or sent anywhere.

### Now Playing

- Track information comes from notifications Music and Spotify broadcast on the Mac. Reading it needs no permission and nothing is stored.
- Playback controls, the position and artwork use Apple Events and need your Automation permission, which macOS asks for the first time you press a control. NotchDeck never launches Music or Spotify.
- **Network:** Spotify provides artwork as a link. NotchDeck downloads it over HTTPS, only from Spotify's image servers (`scdn.co`, `spotifycdn.com`), without cookies or a cache (ephemeral session). It is the only network request NotchDeck makes, and it sends nothing about you beyond the image request itself. Music artwork comes from the Music app directly.

### Developer agents

- **Only what tools send.** Claude Code, Codex and other tools you set up report their sessions with `notchctl` over a local socket that only your user account can reach ([`SECURITY.md`](SECURITY.md)). NotchDeck never reads terminals, transcripts or the tools' configuration files, and has no network listener.
- **What a message can contain:** the tool's name, its session ID, a project name, the workspace path, a task, a status, a short status message, progress, and the bundle ID of the terminal or editor the tool runs in.
- **Kept in memory only**, while the session is shown: until it ends or is dismissed, at most an hour after it finishes, and never longer than 8 hours without an update. Quitting NotchDeck or turning Developer agents off forgets every session. Messages are never stored, logged or sent anywhere.
- **Claude Code and Codex hooks forward as little as possible.** The adapters run inside `notchctl`, in the tool's hook, and read only event names, session IDs, the working directory, tool names, notification types and the tools' own notification text (such as "Claude needs your permission to use Bash"); for Claude Code also a session title you chose yourself (`--name`, `/rename`). Your prompts, commands, file paths and contents, tool output, the agents' replies and transcripts are never forwarded.
- **Opt-in:** with `--prompt-as-task` in the hook command, the first line of each prompt (up to 240 characters) is shown as the session's task. Setup: [Claude Code](docs/integrations/claude-code.md), [Codex](docs/integrations/codex.md).
- **The notch is on screen.** Tasks and status messages appear on the notch and in screen shares and recordings, so integrations should never send secrets. Turn off **Settings ▸ Features ▸ Developer agents** to stop listening altogether.

## For Contributors

Any change that reads a new category of user data, adds a permission, stores user data, or communicates off-device must update this document in the same change.
