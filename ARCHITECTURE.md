# Architecture

> **Status: planned, not implemented.** As of Phase 0, the codebase contains only a minimal SwiftUI app shell that launches a placeholder window. Everything below describes the *intended* architecture that Phase 1 will begin to implement. Update this document as reality diverges from the plan.

## Core Principle

> **Features do not own the notch. Features publish activities. The Activity Engine owns what the user sees.**

Features never draw into, resize, show or hide the notch surface directly. They describe what is happening as `NotchActivity` values. A single engine decides what is presented.

## Activity Pipeline

```text
ActivityProvider
       ↓
NotchActivity
       ↓
ActivityStore
       ↓
ActivityResolver
       ↓
NotchStateMachine
       ↓
NotchPresentation
```

| Stage | Responsibility |
| --- | --- |
| **ActivityProvider** | A feature-side source (timer, music, calendar, agent bridge…) that observes something and publishes, updates or withdraws activities. Knows nothing about windows or layout. |
| **NotchActivity** | A value describing one thing that is happening: identity, source, priority, timing/expiry, and the content needed to render it at each disclosure level. |
| **ActivityStore** | The single source of truth for all currently live activities. Handles insert/update/remove and expiry. |
| **ActivityResolver** | Decides which activity (or activities) deserve the notch right now, based on priority, recency, user preferences and context. (Referred to as *PriorityResolver* in `AGENTS.md`; the name will be finalized in Phase 1.) |
| **NotchStateMachine** | Owns the notch's presentation state (Idle, Live Activity, Peek, Expanded, Shelf) and the legal transitions between them, driven by resolver output and user interaction. |
| **NotchPresentation** | The AppKit/SwiftUI layer: the notch-attached window(s), layout, materials and animation. Renders whatever the state machine says — nothing more. |

Design intentions:

- **Unidirectional flow.** Data flows down the pipeline; user intents flow back up as explicit actions routed to the owning provider.
- **Testable core.** Store, resolver and state machine are plain Swift logic with no UI dependencies, so they can be unit tested exhaustively.
- **Event-driven.** Providers react to system notifications/observers; the pipeline only recomputes on change.

## Activity Priority

Activities carry a priority level used by the resolver. Planned levels, lowest to highest:

```text
Ambient              Background context; shown only when nothing else is relevant.
Passive              Ongoing but low-urgency (e.g. music playing).
Active               Something the user is currently engaged with (e.g. running timer).
Time Sensitive       Relevant now and soon stale (e.g. meeting starting in 2 minutes).
Attention Required   The user needs to act (e.g. an agent is waiting for input).
Critical             Rare; must be seen immediately (e.g. timer finished, failure needing action).
```

Concrete numerical values, tie-breaking rules, decay over time, and how user preferences modify priority will be finalized during Phase 1 implementation and recorded in an ADR.

## Planned Domains

```text
App            App lifecycle, entry point, dependency wiring.
Core           Activity model, store, resolver, state machine, notch geometry, permissions.
Features       Self-contained features that act as activity providers.
Integrations   Bridges to external tools/apps (e.g. Claude Code, Codex, calendar sources).
Services       Shared system services (audio, system metrics, power assertions, pasteboard).
UI             Presentation layer views for each disclosure level plus shared components.
Settings       User preferences, profiles, per-integration permissions.
Tests          Unit tests for core logic; integration tests where practical.
```

## Suggested Future Source Structure

This is a guide, not a mandate. Directories are created when real code needs them — not as empty placeholders.

```text
NotchDeck/
├── App/
│
├── Core/
│   ├── Activities/
│   ├── Notch/
│   └── Permissions/
│
├── Features/
│   ├── Music/
│   ├── Calendar/
│   ├── Timer/
│   ├── SystemStats/
│   ├── Audio/
│   ├── KeepAwake/
│   ├── Shelf/
│   ├── Clipboard/
│   ├── Agents/
│   └── QuickActions/
│
├── Integrations/
│
├── Services/
│
├── Settings/
│
└── UI/
    ├── Compact/
    ├── Peek/
    ├── Expanded/
    ├── Shelf/
    └── Components/
```

## Current Repository Layout (Phase 0)

```text
NotchDeck.xcodeproj/       Xcode project (file-system-synchronized groups) + shared scheme
NotchDeck/                 App target sources
├── App/NotchDeckApp.swift Placeholder SwiftUI entry point
└── Assets.xcassets/       App icon and accent color (empty)
NotchDeckTests/            Unit tests (Swift Testing)
Scripts/                   Developer scripts
docs/                      Decisions, architecture notes, development notes
```

The Xcode project uses **file-system-synchronized groups**: any file added under `NotchDeck/` or `NotchDeckTests/` is automatically part of the corresponding target — no `.pbxproj` edits needed for new source files.

## Known Open Questions (to resolve in Phase 1+)

- Notch window strategy: window level, which `NSWindow`/`NSPanel` configuration, multi-display and non-notched display behavior.
- Activation policy: Dock icon vs. accessory (menu-bar-style) app.
- App Sandbox: whether NotchDeck can ship sandboxed given planned features.
- Swift concurrency defaults (e.g. main-actor default isolation).
- Agent IPC transport for Phase 5 (must be local and authenticated — see `SECURITY.md`).

## Architecture Decision Records

Significant decisions are recorded as ADRs in [`docs/decisions/`](docs/decisions/), numbered sequentially:

```text
docs/decisions/0001-notch-window-strategy.md
docs/decisions/0002-activity-engine.md
docs/decisions/0003-agent-ipc.md
```

(The above are examples of likely future ADRs; none exist yet.) Write an ADR when a decision is hard to reverse, affects multiple domains, or chooses between real alternatives. ADRs are written when the decision is actually made — never speculatively. See [`docs/decisions/README.md`](docs/decisions/README.md) for the template.
