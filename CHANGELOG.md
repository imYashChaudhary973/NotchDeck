# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project intends to adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once releases begin.

## [Unreleased]

### Added

- Phase 1 — notch foundation:
  - Menu-bar (accessory) app lifecycle with Settings and Quit; Launch at Login via `SMAppService`.
  - Notch geometry from public `NSScreen` APIs, virtual notch on displays without one, display selection (Automatic / Primary) with live screen-change handling.
  - Borderless, non-activating notch panel above the menu bar, on all Spaces and over full-screen apps.
  - Activity Engine: `NotchActivity`, `ActivityPriority` (10–60), `ActivityStore`, `ActivityResolver`, provider protocol, event-driven expiry, queueing, priority interruption and automatic restoration.
  - `NotchStateMachine` with Idle, Live Activity, Peek, Expanded and Shelf; hover, click, outside-click dismissal, attention auto-peek and basic drag detection.
  - SwiftUI notch surface with interruptible spring animations (Reduce Motion respected).
  - Basic settings (hover, collapse, attention peek, display).
  - Debug-only activities panel and provider.
  - 63 unit tests (store, resolver, engine, state machine, geometry, layout, settings).
  - ADRs 0001–0003.
- Six-phase engineering plan (`docs/development/engineering-plan.md`), linked from `ROADMAP.md`, `ARCHITECTURE.md` and `AGENTS.md`.
- Phase 0 repository bootstrap:
  - Minimal SwiftUI macOS app target (`NotchDeck`) and a Swift Testing unit test target (`NotchDeckTests`).
  - Shared `NotchDeck` Xcode scheme.
  - Project documentation: `README.md`, `AGENTS.md`, `PRODUCT.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `DEVELOPMENT.md`, `CONTRIBUTING.md`, `PRIVACY.md`, `SECURITY.md`.
  - `docs/` structure for decisions (ADRs), architecture and development notes.
  - `Scripts/bootstrap.sh` for non-destructive environment diagnostics.
  - GitHub issue templates and pull request template.
  - `.gitignore` and `.editorconfig`.
