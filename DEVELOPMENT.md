# Development

This document describes how to build, run and test NotchDeck locally. Items marked **TBD during Phase 1** have not been decided yet — do not assume values for them.

## Requirements

### macOS version

- **Supported deployment target (minimum macOS for users):** macOS 14.0 Sonoma ([ADR 0003](docs/decisions/0003-app-runtime-configuration.md)).
- **Development machine:** any macOS version that runs the required Xcode.

### Xcode version

- **Required Xcode:** Xcode 16 or later (Swift 6 language mode, `objectVersion 77`). Development and verification use **Xcode 27.0** (Swift 6.4, macOS 27.0 SDK).
- The project uses `objectVersion = 77` (file-system-synchronized groups), which requires **Xcode 16 or later** to open.

### Dependencies

None. No package managers, no third-party frameworks.

## Quick Environment Check

```bash
Scripts/bootstrap.sh
```

Reports macOS/Xcode/Swift versions, Git status and remote, and whether the project is listable. It never modifies anything.

## Opening the Project

```bash
open NotchDeck.xcodeproj
```

Select the shared **NotchDeck** scheme and the **My Mac** destination.

New files placed under `NotchDeck/` or `NotchDeckTests/` are automatically included in their targets (file-system-synchronized groups) — you do not need to edit the project file.

## Building

```bash
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck -configuration Debug build
```

## Running

From Xcode: **Product ▸ Run** (⌘R).

From the command line:

```bash
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck -configuration Debug \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/NotchDeck.app
```

(`build/` is git-ignored.)

NotchDeck is an accessory app: there is no Dock icon or main window. Look for the notch surface and the menu bar item (Settings…, Debug Activities…, Quit).

### Debug Activities panel

Debug builds include a developer-only panel that simulates activities (Music, Meeting, Timer, File Transfer, Claude Waiting, Clipboard, Critical) and drives notch states (Attention Peek, Expand, Shelf, Collapse). It lists live activities with their priorities.

- Open from the menu bar item: **Debug Activities…**, or
- launch with `--args -NotchDeckShowDebugPanel YES`.

Useful launch arguments (they override stored settings for that run):

| Argument | Effect |
| --- | --- |
| `-NotchDeckShowDebugPanel YES` | Open the debug panel at launch (Debug builds) |
| `-notch.displayPreference primary` | Put the notch on the primary display (test the virtual notch on external monitors) |
| `-audio.scrollAdjustsVolume YES` | Turn on scroll-over-the-notch volume for that run |
| `-features.<timers\|keepAwake\|systemMetrics\|audio\|quickActions\|music\|shelf>.enabled NO` | Turn a feature off for that run |
| `-features.calendar.enabled YES` | Turn Calendar on for that run (shows the Allow Access row; does not prompt) |
| `-features.clipboard.enabled YES` | Turn clipboard history on for that run (records copies made after launch) |
| `-shelf.opensOnApproach NO` | The shelf opens only when a drag reaches the notch itself |

## Testing

Tests use **Swift Testing** (`import Testing`).

```bash
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck test
```

In Xcode: **Product ▸ Test** (⌘U).

## Configurations

### Debug

- No optimization (`-Onone`), `DEBUG` compilation condition, testability enabled.

### Release

- Whole-module optimization, dSYM generation, assertions disabled.

## Signing

- Currently: **automatic signing, "Sign to Run Locally"** (`CODE_SIGN_IDENTITY = "-"`), no development team set. This lets anyone build and run locally without an Apple Developer account.
- **Do not commit a personal `DEVELOPMENT_TEAM`** into the shared project. If you need team signing locally, set it in Xcode and do not stage that change, or use a local, git-ignored `.xcconfig` (to be introduced when needed).
- Distribution signing, notarization and Developer ID: TBD during Phase 1 (or later release work).
- Bundle identifier: `com.imyashchaudhary.NotchDeck` (provisional — confirm before first distribution).

## Entitlements

- `NotchDeck/NotchDeck.entitlements`: `com.apple.security.automation.apple-events` (the hardened runtime blocks Apple Events to Music and Spotify without it). Hardened Runtime is enabled. `LSUIElement = YES` (accessory app).
- Usage descriptions (generated Info.plist, `INFOPLIST_KEY_…` build settings): `NSAppleEventsUsageDescription`, `NSCalendarsFullAccessUsageDescription`, `NSCalendarsUsageDescription`.
- App Sandbox: **off for now**; to be revisited before first distribution ([ADR 0003](docs/decisions/0003-app-runtime-configuration.md)).

## Permissions

The notch itself needs **no** permissions (no Accessibility, Input Monitoring or Screen Recording). Planned features will need some of the following, each requested **contextually** when the user enables the feature:

| Feature | Likely permission / mechanism |
| --- | --- |
| Keep Awake | IOKit power assertion — no permission |
| System metrics | Mach host statistics, `sysctl`, IOKit power sources — no permission |
| Audio | CoreAudio HAL — no permission (output only; the microphone is never used) |
| Quick Actions | `NSWorkspace` opens folders and apps — no permission. Screenshot opens the system Screenshot app instead of capturing, so no Screen Recording permission. |
| Now Playing | Distributed notifications from Music / Spotify — no permission. Controls, position and artwork: Automation (Apple Events), asked by macOS the first time a control is pressed |
| Calendar | EventKit full calendar access, asked when Calendar is turned on in Settings |
| Login item | ServiceManagement (`SMAppService`) — implemented; may need approval in System Settings ▸ General ▸ Login Items, and is unreliable for builds run from DerivedData |
| File Shelf | Drag and drop, bookmarks, Quick Look, `NSSharingService` — no permission. The drag-approach monitor is a global *mouse* event monitor, which needs no Accessibility or Input Monitoring permission. |
| Clipboard | `NSPasteboard` — no TCC permission. On macOS 15.4+ the system may show its "Paste from Other Apps" prompt on the first read, which NotchDeck does only right after the user turns the feature on. Reset with `tccutil reset Pasteboard com.imyashchaudhary.NotchDeck`. |
| Developer agents | Local IPC (design TBD in Phase 5) |

Usage-description strings (`NS…UsageDescription`) are added alongside the feature that needs them.

To test permission prompts again, reset them: `tccutil reset Calendar com.imyashchaudhary.NotchDeck` and `tccutil reset AppleEvents com.imyashchaudhary.NotchDeck`.

To exercise Now Playing without playing music, post the notification Music sends, for example with a small Swift script calling `DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.apple.Music.playerInfo"), object: nil, userInfo: ["Name": "Song", "Artist": "Artist", "Player State": "Playing", "Total Time": 200000], deliverImmediately: true)`.

## Troubleshooting

- **`xcodebuild` "requires Xcode, but active developer directory … is a command line tools instance":** prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or run `sudo xcode-select -s /Applications/Xcode.app`.
- **"The project is damaged" / cannot open:** you are on an Xcode older than 16. Upgrade Xcode.
- **Signing errors when building:** make sure no `DEVELOPMENT_TEAM` mismatch was introduced; the shared project builds with "Sign to Run Locally".
- **Stale build behavior:** delete DerivedData for the project (`~/Library/Developer/Xcode/DerivedData/NotchDeck-*`, or `build/` if you used `-derivedDataPath build/DerivedData`).
- **`warning: Metadata extraction skipped, no AppIntents.framework dependency found`:** harmless toolchain notice; not caused by project code.
- **Notch not visible / on the wrong display:** check Settings ▸ Notch ▸ Display. With "Automatic", a connected built-in notched display wins over the primary display.
- **Two NotchDecks running:** quit the old one (menu bar item ▸ Quit) before launching a new build; both would draw over the notch.
