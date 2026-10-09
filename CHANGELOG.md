# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project intends to adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once releases begin.

## [Unreleased]

### Added

- Phase 5 — Claude Code, Codex and the generic developer activity protocol:
  - [Developer activity protocol](docs/developer-activity-protocol.md) v1: one versioned JSON message per connection (`event`, `end`, `ping`; nine statuses from `starting` to `cancelled`), validated as untrusted input. Any tool can report sessions; nothing reads terminal screens.
  - Local bridge: a Unix domain socket in `~/Library/Application Support/NotchDeck/Bridge` (directory 0700, socket 0600), connections only from the same user (`getpeereid`), bounded in size, time and concurrency. No network listener. Event-driven; free while idle.
  - `notchctl`, bundled in the app: `agent start|update|working|command|waiting|input|permission|complete|fail|cancel|end`, `send` (raw JSON), `hook <adapter>`, `ping`, with `sysexits` exit codes. Settings shows its path and a symlink command.
  - Claude Code hooks (`notchctl hook claude-code`), Codex lifecycle hooks (`codex`) and Codex `notify` (`codex-notify`) adapters. Prompts, commands, tool input and transcripts are never forwarded (`--prompt-as-task` opts in to a prompt's first line). Setup guides in [`docs/integrations/`](docs/integrations/).
  - Developer agents feature (on by default): one activity per session. Working agents sit above music but below a running timer or an upcoming meeting; agents needing input or permission auto-peek; finished and failed sessions briefly show on the notch, then wait in the command center. Live elapsed time, agent cards with Open Terminal, Open Workspace and Dismiss. Stale sessions are removed.
  - New `agent` content style and `elapsed` compact accessory; Debug panel buttons for simulated agents.
  - [ADR 0008](docs/decisions/0008-developer-activity-bridge.md). 281 new unit tests (596 total).

- Phase 4 — File Shelf and clipboard history:
  - Drops on the notch go through the Activity Engine (`acceptsDrops`, `handleDrop`, `routeDrop`); the notch window stays owned by `NotchController`. The shelf opens as a content drag approaches the notch, before macOS would open the Spaces bar.
  - File Shelf: files, folders, links, text, dropped images and file promises. Three drop tiles (Shelf, Copy, AirDrop). Files are referenced with bookmarks, never copied; missing files are shown as such. Items expire after an hour or at the end of the day, can be kept longer per item or pinned. Drag items out into any app; Quick Look, Open, Copy, Show in Finder, Share, Remove. Quick Look thumbnails at notch size.
  - Clipboard history (off by default): text with small RTF, links, colors, images and file paths, deduplicated, with search (History window), pinning, delete, clear, pause, a maximum size and a retention period. Concealed and transient content, password managers and excluded apps are never kept. macOS 15.4 paste-access states are handled. Stored only on this Mac and never logged.
  - New `collection` content style (tiles and rows) and `shelf` activity kind; horizontal scrolling reaches notch content.
  - [ADR 0007](docs/decisions/0007-shelf-and-clipboard.md). 72 new unit tests (315 total).

- Phase 3 — Now Playing, Calendar and context resolution:
  - Now Playing for Apple Music and Spotify behind a `MediaProvider` abstraction. Track, artist, album, artwork, progress and play/pause/next/previous, each marked unsupported when unavailable. It uses distributed notifications (no permission) and Apple Events (Automation permission, asked on the first control press); no private MediaRemote. NotchDeck never launches a media app. The Live Activity shows the artwork; the expanded card slides in a new track and cross-fades artwork. Paused music moves to the command center.
  - Calendar via EventKit: access requested only when the feature is turned on, with every permission state handled. Calendar selection, a configurable look-ahead (3/6/12/24 h) and notch timing (5/10/15/30 min). The next meeting escalates on the notch (30 at 15 min, 40 at 5 min, 50 from 1 min before, with an auto-peek). It shows "Starting now" with Join for 5 minutes, then expires. A schedule appears in the command center. Meeting links are found in the event URL, location or notes (Zoom, Meet, Teams, Webex, FaceTime and more). EventKit is queried only on changes and every 6 h; otherwise the provider wakes at the next event boundary.
  - Context resolution: an imminent meeting interrupts music, and music returns when the meeting leaves the notch (covered by tests with the real providers).
  - New `schedule` content style; `MediaContent.trackID`; single-line capsule buttons.
  - Apple Events entitlement and usage descriptions for Automation and Calendars.
  - [ADR 0006](docs/decisions/0006-media-and-calendar-providers.md). 65 new unit tests (243 total).
- Phase 2 — local utility features (no accounts needed):
  - Timers: several at once, presets (5/10/15/25/30 min, 1 hr) and a custom-duration window, pause / resume / +1 min / cancel / restart. Only the most relevant timer takes the notch. Priority rises as a timer nears zero (30 → 35 at one minute → 40 at ten seconds → 50 when finished, for 10 s), with an optional completion sound. Timers are saved, so they survive a relaunch.
  - Keep Awake: a supported IOKit power assertion for 30 min, 1 hr, 2 hr or until turned off, with a subtle Live Activity while on. Released when the session ends, when the feature is turned off and when the app quits. An active session is restored after relaunch.
  - System metrics: CPU, memory (colored by memory pressure) and battery in the command center, plus a brief Charging peek. CPU and memory are sampled every 2 s, and only while visible. Battery and memory pressure are event-driven.
  - Audio: output volume (draggable level bar), mute, and output-device selection through CoreAudio. Optional scroll-over-the-notch volume with a HUD.
  - Quick Actions: an extensible `QuickAction` protocol and a grid with Timer, Keep Awake, Downloads, Applications, Activity Monitor, Screenshot and Screen Saver. Lock Screen is unavailable because macOS has no public API for it.
  - Settings ▸ Features: turn each feature off individually. Feature options: timer sound, scroll to change volume. Menu bar: Start Timer and Keep Awake submenus.
  - Engine: `.commandCenter` activity placement, on-screen activity feedback to providers, continuous-value and scroll input routing, and the `actions` content style and options list ([ADR 0005](docs/decisions/0005-local-utility-providers.md)).
  - 77 new unit tests (178 total).
- Phase 1 — notch foundation:
  - Menu-bar (accessory) app lifecycle with Settings and Quit; Launch at Login via `SMAppService`.
  - Notch geometry from public `NSScreen` APIs, virtual notch on displays without one, display selection (Automatic / Primary) with live screen-change handling.
  - Borderless, non-activating notch panel above the menu bar, on all Spaces and over full-screen apps. On displays without a physical notch, the resting virtual notch hides over full-screen apps (detected from public window bounds, no permissions) and still appears for attention peeks.
  - Activity Engine: `NotchActivity`, `ActivityPriority` (10–60), `ActivityStore`, `ActivityResolver`, provider protocol, event-driven expiry, queueing, priority interruption and automatic restoration.
  - `NotchStateMachine` with Idle, Live Activity, Peek, Expanded and Shelf; hover, click, outside-click dismissal, attention auto-peek and basic drag detection.
  - SwiftUI notch surface with interruptible spring animations (Reduce Motion respected); the expanded surface sizes itself to its content, animating any re-fit.
  - Live Activity with 52 pt ears, a 16 pt glyph and 13 pt accessory pinned to the outer edges; compact and Peek rows ride the edges as the surface opens.
  - Off-screen warm-up after launch so the first animation of each state doesn't drop frames.
  - Command-center design: section tabs beside the notch, featured card plus widget column, Now Playing card, metric and toggle rows, segmented volume HUD, approval-style Peek, and shelf drop tiles — driven by new activity content styles (`media`, `level`, `metric`, `toggle`) and simulated in the debug panel ("Command Center Demo", "Volume", "Keep Awake", "System Stats").
  - Basic settings (hover, collapse, attention peek, display).
  - Debug-only activities panel and provider.
  - 101 unit tests (store, resolver, engine, state machine, geometry, layout, compact layout, full-screen visibility, drag description, warm-up samples, settings).
  - ADRs 0001–0004.
- Six-phase engineering plan (`docs/development/engineering-plan.md`), linked from `ROADMAP.md`, `ARCHITECTURE.md` and `AGENTS.md`.
- Phase 0 repository bootstrap:
  - Minimal SwiftUI macOS app target (`NotchDeck`) and a Swift Testing unit test target (`NotchDeckTests`).
  - Shared `NotchDeck` Xcode scheme.
  - Project documentation: `README.md`, `AGENTS.md`, `PRODUCT.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `DEVELOPMENT.md`, `CONTRIBUTING.md`, `PRIVACY.md`, `SECURITY.md`.
  - `docs/` structure for decisions (ADRs), architecture and development notes.
  - `Scripts/bootstrap.sh` for non-destructive environment diagnostics.
  - GitHub issue templates and pull request template.
  - `.gitignore` and `.editorconfig`.
