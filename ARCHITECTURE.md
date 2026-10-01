# Architecture

> The phase-by-phase brief behind this architecture is [`docs/development/engineering-plan.md`](docs/development/engineering-plan.md).

> **Status: Phase 1 implemented.** The notch foundation, Activity Engine and state machine exist and are unit tested. No real integrations exist yet. Only the developer-only debug provider publishes activities. Sections marked *(planned)* describe later phases.

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
| `liveActivity` | Notch plus a 40 pt "ear" on each side: glyph on the leading ear, accessory (countdown, progress ring, symbol) on the trailing ear. |
| `peek` | 360 pt wide: compact row plus title and subtitle. |
| `expanded` | 480 pt wide: primary activity with progress and actions, the next two queued activities, and a Settings button. |
| `shelf` | Drop target. Phase 1 detects drags but refuses drops (the File Shelf is Phase 4). |

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

2. Register it in `AppEnvironment.start()`: `engine.register(TimerProvider())`.
3. To change urgency, republish the same `id` with a new `priority`. Withdraw with `publisher.withdraw(id:)`, or set `expiresAt` and let the engine remove it.
4. Add unit tests for the provider's state logic, and test that it publishes the activities you expect (see `ActivityEngineTests` for a recording provider).

Provider rules:

- Never import or reference `NotchController`, `NotchPanel` or notch views.
- Prefer system notifications and observers. If you must poll, poll only while your activity is live, with timer tolerance.
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

`ActivityPriority` is `Int`-backed, so intermediate values (e.g. 35) are allowed. Decay and user-preference adjustments (profiles) are *(planned)* for Phase 6.

## Domains

```text
App            Entry point (MenuBarExtra), AppDelegate, AppEnvironment (composition root), auxiliary windows.
Core           Activities (model, store, resolver, engine, provider protocol) and Notch (geometry, layout,
               state machine, panel, hosting view, controller, view model).
Features       Activity providers. Phase 1: DebugActivities (Debug builds only).
Integrations   (planned) Bridges to external tools/apps (Apple Music, Spotify, Claude Code, Codex).
Services       Shared system services. Phase 1: LaunchAtLoginService.
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
│                            NotchStateMachine, NotchPanel, NotchHostingView, NotchViewModel, NotchController
├── Features/
│   └── DebugActivities/     DebugActivityProvider, DebugPanelView (#if DEBUG)
├── Services/                LaunchAtLoginService
├── Settings/                AppSettings, SettingsView
└── UI/
    ├── NotchRootView.swift
    ├── Compact/  Peek/  Expanded/  Shelf/
    └── Components/          NotchShape, activity glyph/accessory/progress components
NotchDeckTests/
├── Activities/              store, resolver, engine tests
├── Notch/                   state machine, geometry, layout tests
└── Settings/                settings persistence tests
```

Future features follow the same pattern: `Features/<Name>/`, plus `Integrations/<Service>/` when an external app or tool is involved. Directories are created when real code needs them.

The Xcode project uses **file-system-synchronized groups**: any file added under `NotchDeck/` or `NotchDeckTests/` is automatically part of its target.

## Open Questions

- App Sandbox and distribution (Developer ID, notarization): revisit before first release ([ADR 0003](docs/decisions/0003-app-runtime-configuration.md)).
- Drag "approach" region larger than the notch for the File Shelf (Phase 4).
- Keyboard navigation of the notch surface (Phase 6).
- Agent IPC transport for Phase 5 (`notchctl` → app; must be local and authenticated — see `SECURITY.md`).

## Architecture Decision Records

Significant decisions are recorded in [`docs/decisions/`](docs/decisions/):

- [0001 — Notch window strategy](docs/decisions/0001-notch-window-strategy.md)
- [0002 — Activity engine and notch state machine](docs/decisions/0002-activity-engine.md)
- [0003 — App runtime configuration](docs/decisions/0003-app-runtime-configuration.md)

Write an ADR when a decision is hard to reverse, affects multiple domains, or chooses between real alternatives. See [`docs/decisions/README.md`](docs/decisions/README.md) for the template.
