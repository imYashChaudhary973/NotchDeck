# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project intends to adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once releases begin.

## [Unreleased]

### Added

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
