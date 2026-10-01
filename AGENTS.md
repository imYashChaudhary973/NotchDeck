# AGENTS.md — Instructions for Coding Agents

Every coding agent (human or AI) working on NotchDeck must read this file **before modifying code**, then read [`PRODUCT.md`](PRODUCT.md) and [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## Project Mission

NotchDeck is a native macOS application that turns the MacBook notch into a **contextual command center**.

Potential activities include:

- music
- meetings
- timers
- system controls
- CPU / memory information
- file shelf
- clipboard
- Claude Code activity
- Codex activity
- developer notifications
- quick actions

The application must remain **minimal** despite supporting many capabilities.

---

## The Most Important Architectural Rule

> **Features do not own the notch. Features publish activities. The Activity Engine owns what the user sees.**

No feature may independently create, resize, show, hide or otherwise manipulate the primary notch interface. A feature's only job is to describe what is happening (an activity) and hand it to the engine. The engine decides what is presented, when, and how.

```text
Provider
    ↓
NotchActivity
    ↓
ActivityStore
    ↓
PriorityResolver
    ↓
NotchStateMachine
    ↓
Presentation
```

If a change would let a feature bypass this pipeline, stop and redesign it — or document why in an ADR (`docs/decisions/`) before proceeding.

---

## Agent Rules

Agents must:

1. Read `AGENTS.md`.
2. Read `PRODUCT.md`.
3. Read `ARCHITECTURE.md`.
4. Inspect the existing implementation before changing architecture.
5. Preserve existing working functionality.
6. Prefer small, reviewable changes.
7. Build the project after meaningful implementation changes.
8. Run relevant tests.
9. Fix compiler warnings introduced by their work.
10. Update documentation when architecture changes.
11. Add tests for important business / state logic.
12. Avoid unnecessary dependencies.
13. Prefer Apple frameworks.
14. Prefer event-driven architecture over aggressive polling.
15. Keep idle resource usage extremely low.

Build and test commands are in [`DEVELOPMENT.md`](DEVELOPMENT.md).

---

## Native macOS Rule

Prefer:

```text
Swift
SwiftUI
AppKit
Foundation
EventKit
ServiceManagement
NSPasteboard
CoreAudio
IOKit / supported low-level system APIs where appropriate
```

- Avoid Electron.
- Do not introduce a web-based application shell.
- NotchDeck should behave like a first-class macOS application.

---

## Private API Rule

Do not use undocumented / private Apple frameworks for core functionality.

If a desired capability is unavailable through stable, supported APIs:

1. document the limitation,
2. design a capability abstraction,
3. provide a safe fallback.

Never silently depend on private APIs.

---

## Performance Rule

NotchDeck runs all day. Optimize for:

```text
idle CPU
memory
energy
wakeups
polling frequency
animation cost
background services
```

Prefer system events, notifications and observers over constant polling. When polling is unavoidable, use the lowest reasonable frequency, coalesce timers (with tolerance), and stop polling when nothing is visible or relevant.

---

## Privacy Rule

NotchDeck may access sensitive local information, such as:

- clipboard
- calendar
- filenames
- developer project paths
- currently running tools

Treat all of this as private. Never:

- upload clipboard history without explicit product behavior requiring it
- log clipboard contents
- log sensitive filenames unnecessarily
- collect unnecessary telemetry
- expose a local unauthenticated network service

See [`PRIVACY.md`](PRIVACY.md) and [`SECURITY.md`](SECURITY.md).

---

## Git Rule

Agents must not run:

```text
git reset --hard
git clean -fd
git push --force
```

unless explicitly instructed by the user.

Agents must not discard unknown user modifications. If the working tree contains changes you did not make, leave them alone and do not include them in your commits.

---

## Scope Rule

When given a numbered development phase (see [`ROADMAP.md`](ROADMAP.md)):

> Implement only that phase plus strictly necessary supporting work.

Do not opportunistically implement future phases.

---

## Documentation Map

| File | Purpose |
| --- | --- |
| [`PRODUCT.md`](PRODUCT.md) | What NotchDeck is and the principles behind it |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Planned architecture, domains, priorities, ADR process |
| [`ROADMAP.md`](ROADMAP.md) | Phases, status and completion criteria |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | Building, running, testing, signing |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Branching and review expectations |
| [`PRIVACY.md`](PRIVACY.md) / [`SECURITY.md`](SECURITY.md) | Privacy and security rules |
| [`docs/decisions/`](docs/decisions/) | Architecture Decision Records |
