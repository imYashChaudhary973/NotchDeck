# Architecture

> The phase-by-phase brief behind this architecture is [`docs/development/engineering-plan.md`](docs/development/engineering-plan.md).

> **Status: Phase 5 implemented.** The notch foundation, Activity Engine and state machine (Phase 1), the local utility providers — Timers, Keep Awake, System Metrics, Audio, Quick Actions (Phase 2) — Now Playing (Apple Music, Spotify) and Calendar (Phase 3), the File Shelf and clipboard history (Phase 4), and developer agent activity through the generic developer activity protocol and `notchctl` (Phase 5) exist and are unit tested. Sections marked *(planned)* describe later phases.

## Core Principle

> **Features do not own the notch. Features publish activities. The Activity Engine owns what the user sees.**

Features never draw into, resize, show or hide the notch surface directly. They describe what is happening as `NotchActivity` values. A single engine decides what is presented.

## Activity Pipeline

```text
ActivityProvider ──publish/withdraw──▶ ActivityPublisher (scoped to the provider's source)
                                              │
                                              ▼
                                       ActivityEngine
                                       ├── ActivityStore     all live activities, incl. interrupted ones
                                       └── ActivityResolver  primary activity + priority-ordered queue
                                              │ resolution
                                              ▼
                                       NotchController ──events──▶ NotchStateMachine
                                              │ state
                                              ▼
                                       NotchPanel + SwiftUI (NotchRootView)
```

| Stage | Type | Responsibility |
| --- | --- | --- |
| Provider | `ActivityProvider` (protocol) | Observes something; publishes, updates and withdraws activities; handles its actions. Knows nothing about windows. |
| Activity | `NotchActivity` | Value describing one thing that is happening. Identified by `ActivityKey(source, id)`; republishing an id updates it in place. |
| Store | `ActivityStore` | Value type holding every live activity with insertion order; upsert, remove, expiry. |
| Resolver | `ActivityResolver` | Pure function → `ActivityResolution { primary, queued }`. |
| Engine | `ActivityEngine` | `@MainActor @Observable`. Owns store and resolver, routes actions to providers, and schedules expiry with one timer (no polling). |
| State machine | `NotchStateMachine` | Pure value type: states, events and every transition rule. |
| Controller | `NotchController` | The **only** type that touches the notch window. Turns engine output and AppKit input into events and applies the resulting state. |
| Presentation | `NotchPanel`, `NotchHostingView`, `NotchRootView` and per-state views | Renders whatever the state machine says, nothing more. |

### Resolution rules

1. Expired activities are ignored.
2. Higher priority wins.
3. At equal priority, the currently shown activity keeps the notch (no flapping).
4. Otherwise the most recently published activity wins.
5. Only `.notch` activities can be primary. `.commandCenter` activities (controls and background context) are always queued, so they never keep the notch from being idle ([ADR 0005](docs/decisions/0005-local-utility-providers.md)).

Interrupted activities stay in the store, so **restoration is automatic**. When a meeting (40) that interrupted music (20) expires, music is primary again.

When a new primary activity has priority ≥ Attention Required (or an existing one escalates to it), the controller sends `attentionRequested`. The notch auto-peeks for 5 seconds unless the user is engaging with it.

## Notch States

```text
idle ──activity──▶ liveActivity
  │                    │
  └──hover──▶ peek ◀───┘ hover / attention
               │
             click ──▶ expanded ──outside click / pointer exit / dismiss──▶ resting state
any ──drag enters──▶ shelf ──drag exits / drop──▶ resting state
```

The **resting state** is `liveActivity` when there is a primary activity, otherwise `idle`. Every rule lives in `NotchStateMachine.handle(_:)` and is unit tested ([`NotchStateMachineTests`](NotchDeckTests/Notch/NotchStateMachineTests.swift)). Window strategy, geometry and input handling: [ADR 0001](docs/decisions/0001-notch-window-strategy.md). Engine design: [ADR 0002](docs/decisions/0002-activity-engine.md).

| State | Surface |
| --- | --- |
| `idle` | Exactly the physical notch (or a 180 pt virtual notch on displays without one). |
| `liveActivity` | Notch plus a 52 pt "ear" on each side: glyph pinned to the leading edge, accessory (countdown, elapsed time, progress ring, symbol) to the trailing edge. |
| `peek` | 420 pt wide: icon tile and status beside the notch, then title and subtitle — or a segmented level bar for `level` content (volume HUD). |
| `expanded` | The **command center**, 600 pt wide, height fits its content (56–300 pt below the notch row). Section tabs sit beside the notch; the featured activity gets a large card and the next four go in a widget column. See below. |
| `shelf` | Drop target with three tiles (Shelf / Copy / AirDrop) and the dragged item's name; the tile under the pointer highlights, and a drop anywhere else keeps the item on the shelf. Entered only while a provider accepts drops; it also opens as a drag approaches the notch (see *Drops*). |

### Command center

`CommandCenterLayout` (pure, unit tested) derives the expanded layout from the resolution:

- **Tabs:** *Overview* plus one tab per `ActivityKind` that has live activities (fixed order: music, meeting, timer, shelf, clipboard, transfers, agents, system, quick actions). A purple dot marks tabs with an activity that requests attention. Tabs are hidden when only Overview exists.
- **Featured card:** the first activity of the selected section — in Overview, the engine's primary activity, so priority still decides prominence.
- **Widget column:** the next four activities, then "+N more".

### Activity content styles

Providers choose how their activity is drawn in detail through `ActivityPresentation.content` — they describe data, the notch renders it:

| Content | Rendered as | Intended for |
| --- | --- | --- |
| `.standard` | Title, subtitle, countdown/progress, action buttons | most activities |
| `.media(MediaContent)` | Now Playing card: artwork, transport buttons, playback progress (ticks once a second only while visible and playing). A new `trackID` slides the title in and cross-fades the artwork; the Live Activity shows the artwork in the leading ear. | music |
| `.level(LevelContent)` | Segmented level bar (HUD) | volume (Phase 2) |
| `.metric(MetricContent)` | Small bar with value | CPU, memory (Phase 2) |
| `.toggle(ToggleContent)` | Switch | Keep Awake |
| `.actions(ActionsContent)` | Tile grid on the featured card, button row in the widget column | Quick Actions, timer presets |
| `.schedule(ScheduleContent)` | List of timed entries (time, calendar color, title, Now, Join) on the featured card; the subtitle in the widget column | calendar schedule |
| `.collection(CollectionContent)` | Items as a horizontal strip of tiles or as rows, each clickable, with a context menu (actions, Share) and draggable out when it has a payload; the first thumbnails in the widget column | File Shelf, clipboard history |
| `.agent(AgentContent)` | Agent card: provider, project, task, a colored status dot (`Tone`: working, attention, success, failure, neutral), elapsed time (frozen at `endedAt`), progress, actions; "Claude · Rove" and status in the widget column | developer agent sessions |

`.level` can be interactive: with `adjustActionID` the bar is draggable, and with `muteActionID` it gets a mute button. `ActivityPresentation.options` adds a selectable list to the featured card (output devices).

`CompactAccessory.elapsed(since:)` shows time since a date in the trailing ear. Like `.countdown`, it is drawn by `Text(timerInterval:)`, so the app runs no timer for it.

Controls (transport buttons, switches, tiles, options) invoke action IDs that the engine routes back to the owning provider (`ActivityEngine.perform(actionID:on:)`). Continuous controls send a `0…1` value through `ActivityEngine.adjust(actionID:to:on:)`. `statusText` is a short status for Peek (e.g. "Needs approval"); `revealsOnUpdate` makes HUD-style activities briefly reveal the notch on every update (`NotchController.shouldReveal`).

## Placement, Display Feedback and Input Routing

Phase 2 added three engine capabilities ([ADR 0005](docs/decisions/0005-local-utility-providers.md)):

- **Placement.** `NotchActivity.placement` is `.notch` (default) or `.commandCenter`. Command-center activities are listed only in the expanded command center. For them, priority only orders the list.
- **Display feedback.** `NotchController` reports the activities on screen (`NotchDisplay.displayedKeys`) to `ActivityEngine.updateDisplayedActivities(_:)`. Providers hear about their own through `displayedActivitiesChanged(_:)` and can pause work nobody can see.
- **Input routing.** `adjust(actionID:to:on:)` delivers continuous values. `handleNotchScroll(_:)` delivers vertical scrolls over the notch in normalized steps (`NotchScroll`); the first provider that returns `true` handles the scroll. Horizontal scrolls, and vertical ones nobody handles, reach the content (the shelf's tile strip).

### Drops

Phase 4 ([ADR 0007](docs/decisions/0007-shelf-and-clipboard.md)) routes content dropped on the notch through the engine, so no feature touches the window:

- A provider opts in with `acceptsDrops` and receives drops in `handleDrop(_ drop: NotchDrop) -> Bool`. `ActivityEngine.acceptsDrops` is true while a registered provider accepts drops; `routeDrop(_:)` offers a drop to them in registration order.
- `NotchController` accepts a drag only while the engine accepts drops, the drag carries a readable type and it isn't NotchDeck's own. On drop it reads the pasteboard (`NotchDrop.items(from:)`: files, then file promises, then image/PDF data, then web links, then text), picks the tile under the pointer (`ShelfDropTargeting`) and calls `routeDrop`.
- `DragApproachMonitor` (global mouse-event monitor, no permission) feeds `DragApproachTracker` (pure), which opens the shelf when a content drag enters a region around the notch, before the pointer reaches the top edge where macOS would open the Spaces bar. It runs only while a provider accepts drops and the setting is on.

## Providers

| Provider | Source | Activities | System access (public APIs) | Wakes up |
| --- | --- | --- | --- | --- |
| `TimerProvider` | `timer` | One per timer; only the most relevant (finished › soonest running › paused) is `.notch`. Plus a `.commandCenter` "New Timer" presets row. | — (state in `UserDefaults`) | Only at the next phase change: 1 min left, 10 s left, zero, end of alert |
| `KeepAwakeProvider` | `keepAwake` | Keep Awake switch: `.commandCenter` while off, ambient `.notch` Live Activity while on | IOKit `IOPMAssertionCreateWithProperties` (`PreventUserIdleDisplaySleep`, with a system timeout as a safety net) | At the end of a timed session |
| `SystemMetricsProvider` | `systemMetrics` | CPU, memory (colored by memory pressure), battery (`.commandCenter`). Brief "Charging" peek when power connects. | Mach `host_statistics(64)`, `sysctl kern.memorystatus_vm_pressure_level`, `DispatchSource` memory pressure, IOKit power-source notifications | Every 2 s while CPU/memory are on screen; otherwise only on battery and pressure events |
| `AudioProvider` | `audio` | Volume level (draggable, mute, output device options), `.commandCenter`. A `.notch` HUD for 1.5 s after a scroll over the notch (opt-in setting). | CoreAudio HAL: default output device, virtual main volume, mute, device list, property listeners | Only on CoreAudio change notifications |
| `QuickActionsProvider` | `quickActions` | Quick Actions grid (`.commandCenter`) | `NSWorkspace` (Downloads, Applications, Activity Monitor, Screenshot app, Screen Saver) | Never |
| `MusicProvider` | `music` | Now Playing: `.notch` Passive (20) while playing, `.commandCenter` (22) while paused, withdrawn when stopped | Through `MediaProvider`s: distributed notifications and Apple Events (Automation permission, asked on first control) | Only on player notifications |
| `CalendarProvider` | `calendar` | The next meeting on the notch (30 → 40 → 50 as it approaches), the schedule (`.commandCenter`), an access row while not allowed | EventKit (full access, asked when the feature is turned on) | At the next rule boundary or event start/end; once a minute while a countdown is on the notch; EventKit queried on changes and every 6 h |
| `ShelfProvider` | `shelf` | The shelf's items (`.commandCenter`, 25, `.collection` tiles); a 2.5 s "Added to Shelf" / "Copied" confirmation on the notch after a drop | Bookmarks, `NSFilePromiseReceiver`, `QLThumbnailGenerator`, `QLPreviewPanel`, `NSWorkspace`, `NSSharingService` (AirDrop) | Only at the next item expiry |
| `ClipboardProvider` | `clipboard` | Recent clipboard entries (`.commandCenter`, 16, `.collection` rows); an access row when macOS doesn't allow reading. Off by default. | `NSPasteboard` change count, then contents only after a change; `accessBehavior` (macOS 15.4+) | Once a second while on, not paused and the screens are awake; once at the next retention expiry |
| `DeveloperActivityProvider` | `developer` | One `.agent` activity per developer tool session (working 25, waiting 30, needs input/permission 50; finished sessions move to the command center); a "Developer bridge unavailable" row with Retry if the socket can't be opened | A Unix domain socket (`DeveloperBridgeServer`); `NSRunningApplication`, `NSWorkspace` for the session actions | Only when a message arrives, and once at the next rule boundary |

Timer priorities: running 30, last minute 35, last 10 s 40, finished 50 (for 10 s, then removed), paused 20. Running timers store their end date, so they stay accurate across sleep and relaunch; the countdown is drawn by `Text(timerInterval:)`.

Quick actions implement the `QuickAction` protocol (`id`, `title`, `symbolName`, `availability`, `isActive`, `perform()`), and only `.available` ones are shown. **Lock Screen** is `.unavailable`: macOS has no public API for it. **Screen Saver** is the safe fallback; it locks the Mac when "Require password after screen saver begins" is on. **Screenshot** opens the system Screenshot app, so NotchDeck needs no Screen Recording permission. Listing expensive processes ("where permitted") is not implemented.

### Music: `MediaProvider`

`MusicProvider` never talks to a music service directly. It combines `MediaProvider`s — one per media app — and shows the player that most recently started playing (otherwise the most recently paused one). [ADR 0006](docs/decisions/0006-media-and-calendar-providers.md) has the details.

```swift
@MainActor protocol MediaProvider: AnyObject {
    var id: String { get }; var name: String { get }
    var nowPlaying: NowPlaying? { get }          // title, artist, album, state, position, duration, artwork, trackID
    var capabilities: MediaCapabilities { get }  // artwork, progress, playPause, nextTrack, previousTrack
    var controlAccess: MediaControlAccess { get } // undetermined / granted / denied (Automation)
    func startObserving(onChange: @escaping @MainActor () -> Void)
    func stopObserving()
    func send(_ command: MediaCommand)
    func refresh()                                // re-read what the app doesn't announce (position after a seek)
}
```

- Missing capabilities are hidden in the notch: no transport buttons, no artwork, or no progress bar. With control denied, an "Allow Control…" button opens System Settings ▸ Privacy & Security ▸ Automation.
- `ScriptableMediaProvider` (`Integrations/MediaApps/`) implements it for scriptable apps described by a `ScriptableMediaApp` (`AppleMusicApp`, `SpotifyApp`). It reads playback from the app's distributed notification (no permission). It reads the position and artwork and sends commands with Apple Events, off the main thread. It never launches the app.
- No private frameworks (MediaRemote), so other apps' playback (browsers, podcasts) is not shown. To add a player, write another `ScriptableMediaApp` (or `MediaProvider`) and list it in `AppEnvironment`.

### Calendar: `CalendarProvider`

- Reads events through the `CalendarStore` protocol (`EventKitCalendarStore`, read-only; tests use a fake). Cancelled and declined events are dropped. Calendars can be excluded in Settings.
- **Rules** (`CalendarRules`, pure): a meeting takes the notch `notchLeadTime` before it starts (default 15 min, Active 30). It becomes Time Sensitive (40) at 5 min and Attention Required (50, auto-peek) 1 min before. It stays as "Starting now" for 5 min (capped at its end), then leaves the notch. All-day events are listed only. Only the soonest qualifying meeting is a notch activity. Its ear shows minutes ("12m", "Now"), and its Peek status reads "In 12 min" / "Starting now".
- **Actions**: Join opens the meeting link found by `MeetingLinkDetector` (event URL, location, then notes; known services only; `https`/`http` only) and takes the meeting off the notch. So does Dismiss. The schedule has a Join button per entry.
- **Schedule** (`.commandCenter`, `.schedule` content): events in progress or starting within the look-ahead (default 12 h), up to six.
- **Permission**: off by default; access is requested only when the user turns Calendar on (or presses Allow Access… in the command center or Settings). Without access the provider publishes only an access row; it never prompts on launch.
- **Scheduling**: EventKit is queried on start, on `EKEventStoreChanged`, clock or day changes, wake, and every 6 h (each query reaches look-ahead + 6 h). Otherwise the provider sleeps until the next boundary of a cached event.

### File Shelf: `ShelfProvider`

- **Model** (`ShelfCollection`, pure): newest first; dropping the same file, link or text again moves it to the front, keeping its pin and the longer retention; at most 30 items (oldest unpinned leave). Each item expires after the lifetime setting (1 hour or end of day), can be kept longer per item, or is pinned.
- **Storage** (`ShelfStoring`, `ShelfDirectoryStorage`): the item list in `~/Library/Application Support/NotchDeck/Shelf/shelf.json`. Files and folders are bookmarks (`ShelfFileReference`), never copied; a file that can't be found is shown as Missing. Only received file promises and dropped image/PDF data are written, one directory per item, deleted with it.
- **Drop tiles**: Shelf keeps the drop; Copy puts it on the clipboard (`PasteboardWriting`); AirDrop opens `NSSharingService(.sendViaAirDrop)`. Neither of the last two keeps anything.
- **Actions**: Quick Look, Open, Copy, Show in Finder, Share, Keep for 1 Hour, Keep Until Tonight, Pin/Unpin, Remove; drag out into any app. Thumbnails (Quick Look, 48 pt) are made off the main thread after the shelf has been on screen.

### Clipboard history: `ClipboardProvider`

- **Off by default.** While on, the provider reads `NSPasteboard.changeCount` once a second; contents are read only after a change. It never reads concealed/transient content, copies from password managers or excluded apps, its own writes, or what was copied before it started (except once, right after the user turns it on, so any macOS prompt appears in context).
- **Model** (`ClipboardCapture`, `ClipboardHistory`, pure): classification (files, color, link, code, text with small RTF, image), SHA-256 deduplication, maximum unpinned entries, retention, pins, clearing and search.
- **Storage** (`ClipboardStoring`, `ClipboardDirectoryStore`): `~/Library/Application Support/NotchDeck/Clipboard/history.json` and an `Images` directory, written a second after the last change.
- **UI**: the command center lists the five most recent entries (pinned first) with Search History, Pause and Clear; the History window (`ClipboardHistoryView`) searches every entry.

### Developer agents: `DeveloperActivityProvider`

Phase 5 ([ADR 0008](docs/decisions/0008-developer-activity-bridge.md)). The app speaks one tool-neutral protocol, the [developer activity protocol](docs/developer-activity-protocol.md); nothing in the app knows Claude Code or Codex beyond a display name and symbol.

```text
Claude Code / Codex hook ─▶ notchctl hook <adapter> ─┐
any tool or script ───────▶ notchctl agent|send ─────┼─▶ bridge.sock ─▶ DeveloperBridgeServer ─▶ DeveloperActivityProvider ─▶ engine
                                                     ┘   (JSON, v1)      (DeveloperEventSource)
```

- **Transport** (`Services/DeveloperBridge`): a Unix domain socket at `~/Library/Application Support/NotchDeck/Bridge/bridge.sock`, mode 0600 in a 0700 directory. A connection is closed unread unless `getpeereid` reports the user's own uid. One JSON object (at most 16 KiB) per connection, ended by a newline or EOF, read within 2 s; one JSON response. At most 8 connections at once. Dispatch sources wake the listener only on connections, so it costs nothing idle. A stale socket is replaced; a socket another NotchDeck answers on, or a file that isn't a socket, is left alone. No network listener, no tokens.
- **Protocol** (`Shared/DeveloperProtocol`, compiled into the app and `notchctl`): `DeveloperBridgeMessage` (version 1; type `event`, `end` or `ping`), validated as untrusted input: strict ID patterns, sanitized and truncated text (control and bidi characters removed), absolute standardized workspace paths, progress 0…1.
- **`notchctl`** (`notchctl/`, `Shared/CommandLine`): a command-line tool embedded at `NotchDeck.app/Contents/MacOS/notchctl`. `agent <event>`, `send`, `hook <adapter>`, `ping`. Exit codes 0, 64 (usage), 65 (invalid message), 69 (NotchDeck not reachable), 70 (rejected or failed). `hook` never disturbs the calling tool: it always exits 0, prints nothing to standard output and gives up after ~1 s.
- **Tool adapters** (`Shared/AgentAdapters`): `claude-code` (Claude Code hooks), `codex` (Codex lifecycle hooks) and `codex-notify` (Codex's legacy `notify`) translate a tool's hook payload into protocol messages inside `notchctl`, so tool- and version-specific parsing stays out of the app. They never forward prompts, tool input or transcripts (`--prompt-as-task` opts in to the prompt's first line). They are compiled into the app only so they can be unit tested.
- **Sessions** (`DeveloperSessionCollection`, pure): keyed by provider + session ID, else workspace, else project; at most 12. Fields a message leaves out keep their values; a finished session that becomes active again starts a new task.
- **Rules** (`DeveloperActivityRules`, pure):

| Status | On the notch | Then |
| --- | --- | --- |
| starting, working, running command | 25 (above music, below a running timer or a meeting 15 min away) | removed after 30 min without an update |
| waiting | 30 | removed after 30 min without an update |
| needs input, needs permission | 50 (auto-peek) | removed after 8 h without an update |
| completed | 30 for 10 s ("Rove finished") | command center (15) until dismissed, at most 1 h |
| failed | 50 for 30 s | command center (18) until dismissed, at most 1 h |
| cancelled | 20 for 5 s | removed |

- **Actions**: Open Terminal brings forward the session's terminal or editor if it is on an allowlist (`DeveloperApps`) and running, otherwise opens the workspace in Terminal; Open Workspace shows it in Finder; Dismiss removes the session. Workspace paths are opened only when absolute, existing directories (symlinks resolved) that aren't packages.
- **Setting**: Settings ▸ Features ▸ Developer agents, on by default. While off, the provider is unregistered and the socket is closed and removed.

### Context resolution

Competing activities are resolved by priority alone; Phase 3 needed no resolver change ([ADR 0006](docs/decisions/0006-media-and-calendar-providers.md)). Music (20) is interrupted by a meeting within 15 minutes (30). The meeting escalates to 40 and then 50, which peeks once. When it leaves the notch (grace over, joined or dismissed), music is primary again. A running timer (30) keeps the notch against an upcoming meeting (30) until the meeting reaches 40. A working agent (25) takes the notch from music but never from a running timer or a meeting 15 minutes away; an agent that needs input or permission (50) beats a meeting 5 minutes away (40). Paused music is in the command center and never comes back to the notch. `ContextResolutionTests` cover these sequences with the real providers.

Each feature can be turned off in Settings ▸ Features. `AppEnvironment` registers a provider only while its feature is on. Turning a feature off unregisters it, cancelling timers, releasing Keep Awake or emptying the shelf (clipboard history is kept until cleared in Settings). Quitting keeps saved timers and an active Keep Awake session for the next launch.

## Adding a Feature: Registering an Activity Provider

1. Create `NotchDeck/Features/<Feature>/<Feature>Provider.swift`:

    ```swift
    @MainActor
    final class TimerProvider: ActivityProvider {
        let source = ActivitySource(rawValue: "timer")
        private var publisher: ActivityPublisher?

        func start(publisher: ActivityPublisher) {
            self.publisher = publisher      // begin observing; publish when something happens
        }

        func stop() {
            // release observers/assertions; the engine withdraws your activities automatically
        }

        func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
            // handle "pause", "cancel", … for your activities
        }

        private func timerStarted(end: Date) {
            publisher?.publish(NotchActivity(
                id: "timer",
                source: source,
                kind: .timer,
                priority: .active,
                title: "Focus",
                expiresAt: nil,
                presentation: ActivityPresentation(symbolName: "timer", accent: .orange,
                                                   compactAccessory: .countdown(to: end)),
                actions: [ActivityAction(id: "cancel", title: "Cancel", systemImage: "xmark")]
            ))
        }
    }
    ```

2. Create it in `AppEnvironment` and register it in `start()`. Features are listed in `Feature` (`AppSettings`) and registered only while enabled. A feature that needs a permission asks for it when the user turns it on (see Calendar), never at launch.
3. To change urgency, republish the same `id` with a new `priority`. Withdraw with `publisher.withdraw(id:)`, or set `expiresAt` and let the engine remove it.
4. Add unit tests for the provider's state logic, and test that it publishes the activities you expect (see `ActivityEngineTests` for a recording provider).

Provider rules:

- Never import or reference `NotchController`, `NotchPanel` or notch views.
- Prefer system notifications and observers. If you must poll, poll only while your activity is on screen (`displayedActivitiesChanged`), with timer tolerance.
- Use `placement: .commandCenter` for controls and background context that should never occupy the notch on their own.
- Put system access behind a small protocol so the provider's logic can be tested with a fake.
- Use `.countdown(to:)` for ticking time. The system renders it with no app-side timer.
- Never put sensitive content (clipboard text, file contents) in `title` or `subtitle` without a product reason, and never log it.

`DebugActivityProvider` (`Features/DebugActivities/`) is a complete working example.

## Activity Priority

```text
10  Ambient              Background context; shown only when nothing else is relevant (e.g. CPU stats).
20  Passive              Ongoing but low-urgency (e.g. music playing, clipboard).
30  Active               Something the user is engaged with (e.g. running timer, file transfer).
40  Time Sensitive       Relevant now and soon stale (e.g. meeting in 3 minutes, timer < 10 s).
50  Attention Required   The user needs to act (e.g. an agent is waiting for input). Auto-peeks.
60  Critical             Rare; must be seen immediately. Auto-peeks.
```

`ActivityPriority` is `Int`-backed, so intermediate values (e.g. 35) are allowed. For `.commandCenter` activities, priority only orders the command center list. Decay and user-preference adjustments (profiles) are *(planned)* for Phase 6.

## Domains

```text
App            Entry point (MenuBarExtra), AppDelegate, AppEnvironment (composition root), auxiliary windows.
Core           Activities (model, store, resolver, engine, provider protocol) and Notch (geometry, layout,
               state machine, panel, hosting view, controller, view model).
Features       Activity providers: Timers, KeepAwake, SystemMetrics, Audio, QuickActions, Music, Calendar, Shelf, Clipboard,
               DeveloperActivity; DebugActivities (Debug builds only).
Integrations   Bridges to external apps: MediaApps (Apple Music, Spotify). Claude Code and Codex are integrated through
               hook adapters in notchctl (Shared/AgentAdapters), not in the app.
Services       Shared system services: LaunchAtLoginService, PasteboardWriter, DeveloperBridge (the local socket).
Shared         Code compiled into both the app and notchctl: DeveloperProtocol, CommandLine, AgentAdapters.
notchctl       The command-line tool developer tools call.
UI             SwiftUI views per state (Compact, Peek, Expanded, Shelf) and Components.
Settings       AppSettings (UserDefaults-backed, Observable) and SettingsView.
```

## Source Layout

```text
NotchDeck/
├── App/                     NotchDeckApp, AppDelegate, AppEnvironment, AuxiliaryWindowPresenter
├── Core/
│   ├── Activities/          NotchActivity, ActivityPriority, ActivityStore, ActivityResolver,
│   │                        ActivityEngine, ActivityProvider (+ ActivityPublisher)
│   └── Notch/               NotchGeometry (+ DisplayPreference, NotchScreenSelector), NotchLayout,
│                            FullScreenCoverage (+ NotchVisibility), NotchDisplay (+ NotchScroll),
│                            NotchStateMachine, NotchPanel, NotchHostingView, NotchViewModel, NotchController,
│                            NotchDrop (+ ShelfDropTargeting), DragApproach (tracker + monitor)
├── Features/
│   ├── Timers/              CountdownTimer (+ TimerCollection, TimerRules), TimerProvider, CustomTimerView
│   ├── KeepAwake/           KeepAwakeProvider (+ KeepAwakeSession), PowerAssertion
│   ├── SystemMetrics/       SystemMetrics (values + protocols), SystemStatistics (Mach/IOKit), SystemMetricsProvider
│   ├── Audio/               AudioOutput (model + protocol), CoreAudioOutput, AudioProvider
│   ├── QuickActions/        QuickAction (+ built-in actions), QuickActionsProvider
│   ├── Music/               MediaProvider (+ NowPlaying, MediaCapabilities), MusicProvider
│   ├── Calendar/            CalendarEvent (+ CalendarStore), CalendarRules (+ MeetingCountdown), MeetingLinkDetector,
│   │                        CalendarProvider, EventKitCalendarStore
│   ├── Shelf/               ShelfItem (+ ShelfCollection, ShelfLifetime), ShelfStorage, ShelfSystem, ShelfProvider
│   ├── Clipboard/           ClipboardHistory, ClipboardCapture (+ ColorParser), ClipboardPasteboard, ClipboardStore,
│   │                        ClipboardProvider, ClipboardHistoryView
│   ├── DeveloperActivity/   DeveloperActivity (+ DeveloperSessionCollection), DeveloperActivityRules, DeveloperEventSource,
│   │                        DeveloperWorkspace (+ DeveloperApps, DeveloperWorkspaceValidator), DeveloperActivityProvider
│   └── DebugActivities/     DebugActivityProvider, DebugPanelView (#if DEBUG)
├── Integrations/
│   └── MediaApps/           ScriptableMediaApp (+ AppleMusicApp, SpotifyApp), ScriptableMediaProvider,
│                            AppleScriptRunner, ArtworkLoader
├── Services/                LaunchAtLoginService, PasteboardWriter,
│                            DeveloperBridge/ (DeveloperBridgeServer, DeveloperBridgeListener)
├── Settings/                AppSettings, SettingsView
└── UI/
    ├── NotchRootView.swift
    ├── NotchPrewarmer.swift  off-screen first-render warm-up
    ├── Compact/  Peek/  Expanded/  Shelf/
    └── Components/          NotchShape, activity glyph/accessory/progress components
Shared/                      compiled into NotchDeck and notchctl
├── DeveloperProtocol/       DeveloperBridgeMessage, DeveloperBridgeLocation (+ TerminalHint), DeveloperBridgeFraming,
│                            UnixSocket, DeveloperBridgeClient
├── CommandLine/             NotchctlCommand (parsing), NotchctlOutput (exit codes, help)
└── AgentAdapters/           AgentHookAdapter (+ registry), AgentHookSupport, ClaudeCodeHookAdapter, CodexHookAdapters
notchctl/                    main, NotchctlRunner (I/O only)
NotchDeckTests/
├── Activities/              store, resolver, engine, placement, input-routing and context-resolution tests
├── Features/                timer, keep awake, system metrics, audio, quick actions, music, media-app parsing,
│                            calendar rules, meeting links, calendar provider, shelf, clipboard and developer activity
│                            tests (with fakes)
├── DeveloperBridge/         protocol validation, notchctl parsing, socket server round trips and notchctl end to end
├── Integrations/            Claude Code and Codex hook adapter tests
├── Notch/                   state machine, geometry, layout, compact layout, full-screen visibility, drag description,
│                            drag approach and drop routing, display, warm-up tests
└── Settings/                settings persistence tests
```

Future features follow the same pattern: `Features/<Name>/`, plus `Integrations/<Service>/` when an external app or tool is involved. Directories are created when real code needs them.

The Xcode project uses **file-system-synchronized groups**: any file added under `NotchDeck/` or `NotchDeckTests/` is automatically part of its target. Files under `Shared/` belong to both the app and the `notchctl` command-line target, files under `notchctl/` only to the latter; put only `.swift` files there. The app target embeds `notchctl` in `Contents/MacOS`.

## Open Questions

- App Sandbox and distribution (Developer ID, notarization): revisit before first release ([ADR 0003](docs/decisions/0003-app-runtime-configuration.md)).
- Security-scoped bookmarks for shelf files once the App Sandbox is enabled ([ADR 0007](docs/decisions/0007-shelf-and-clipboard.md)).
- Keyboard navigation of the notch surface (Phase 6).
- Bridge peer checks beyond the user ID (code signature of the connecting process) once NotchDeck is Developer ID signed, and the socket's location under the App Sandbox ([ADR 0008](docs/decisions/0008-developer-activity-bridge.md)).

## Architecture Decision Records

Significant decisions are recorded in [`docs/decisions/`](docs/decisions/):

- [0001 — Notch window strategy](docs/decisions/0001-notch-window-strategy.md)
- [0002 — Activity engine and notch state machine](docs/decisions/0002-activity-engine.md)
- [0003 — App runtime configuration](docs/decisions/0003-app-runtime-configuration.md)
- [0004 — Command center presentation](docs/decisions/0004-command-center-presentation.md)
- [0005 — Local utility providers](docs/decisions/0005-local-utility-providers.md)
- [0006 — Media and calendar providers](docs/decisions/0006-media-and-calendar-providers.md)
- [0007 — File Shelf and clipboard history](docs/decisions/0007-shelf-and-clipboard.md)
- [0008 — Developer activity bridge](docs/decisions/0008-developer-activity-bridge.md)

Write an ADR when a decision is hard to reverse, affects multiple domains, or chooses between real alternatives. See [`docs/decisions/README.md`](docs/decisions/README.md) for the template.
