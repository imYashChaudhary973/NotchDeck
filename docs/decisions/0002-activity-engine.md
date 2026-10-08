# 0002. Activity Engine and Notch State Machine

- Status: Accepted
- Date: 2026-10-02

## Context

Many features (music, meetings, timers, agents, clipboard…) compete for one small surface. If each feature drives the notch directly, the result is clutter and race conditions. The architectural rule is: *features publish activities; the Activity Engine owns what the user sees.*

## Decision

### Activities

`NotchActivity` is a value type. It is identified by `ActivityKey(source, id)`, so publishing the same id again updates the activity in place. It carries:
- `kind`
- `priority`
- `title` and `subtitle`
- `startedAt`
- optional `expiresAt` and `progress`
- a descriptive `ActivityPresentation`: SF Symbol, semantic accent and compact accessory (text, symbol, system-rendered countdown, or progress ring)
- `actions`

### Priority

`ActivityPriority` is an `Int`-backed struct with named levels 10–60 (Ambient, Passive, Active, Time Sensitive, Attention Required, Critical). Intermediate values are allowed. Attention Required and above "request attention" and auto-peek.

### Pipeline

```text
ActivityProvider → ActivityPublisher → ActivityEngine
                                         ├─ ActivityStore      (value type: upsert / remove / expiry)
                                         └─ ActivityResolver   (pure: primary + queue)
                                       → resolution → NotchController → NotchStateMachine → NotchPanel / SwiftUI
```

- **ActivityProvider** (`@MainActor` protocol): `start(publisher:)`, `stop()`, `perform(actionID:on:)`. Providers get a source-scoped `ActivityPublisher` and cannot publish for other sources.
- **ActivityStore**: keeps every live activity, including interrupted ones, with insertion order.
- **ActivityResolver** rules:
  1. Expired activities are ignored.
  2. Higher priority wins.
  3. At equal priority, the incumbent keeps the notch (no flapping).
  4. Otherwise the newest wins.
  
  Restoration is automatic: when an interrupting activity is removed, the next resolution picks the interrupted one again.
- **ActivityEngine** (`@MainActor @Observable`): owns the store and the resolver, routes actions to providers, and publishes `resolution`. Expiry is **event-driven**: one task sleeps until the earliest `expiresAt` (continuous clock, 250 ms tolerance). There is no polling.
- **NotchStateMachine**: a pure value type with states `idle`, `liveActivity`, `peek`, `expanded`, `shelf` and explicit events (pointer, click, outside click, dismiss, drag, attention, peek timeout, activity availability). The resting state is `liveActivity` when there is a primary activity, otherwise `idle`. All transition rules live here and are unit tested, including a randomized event-storm invariant test.
- **NotchController** is the only type that touches the panel. It turns engine output and AppKit input into events and applies the resulting state (frame, tracking, monitors, attention-peek timeout).

## Alternatives Considered

- **Features own sub-views of the notch.** Rejected: this is the clutter and race-condition problem the rule exists to prevent.
- **Combine pipelines.** Observation plus a plain change callback is simpler and has no extra dependency.
- **Periodic expiry sweeps.** Rejected for idle cost.
- **Enum priorities.** Too rigid for intermediate values such as a timer at 35.

## Consequences

- New features only implement `ActivityProvider` and register in `AppEnvironment.start()`.
- Store, resolver and state machine are fully testable without UI.
- Profiles (Phase 6) can later adjust effective priority inside the resolver without touching providers.
