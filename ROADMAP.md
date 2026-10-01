# Roadmap

Development proceeds in numbered phases. When working on a phase, implement only that phase plus strictly necessary supporting work (see the Scope Rule in [`AGENTS.md`](AGENTS.md)).

The detailed brief for every phase — including its *Coding Agent Prompt* — is in [`docs/development/engineering-plan.md`](docs/development/engineering-plan.md). This file tracks status and completion criteria.

**MVP cut line:** a releasable early beta can exist after Phase 4. Phase 5 adds the developer differentiator; Phase 6 productizes.

| Phase | Title | Status |
| --- | --- | --- |
| 0 | Repository bootstrap | **Complete** |
| 1 | Notch foundation + Activity Engine + State Machine | **In Review** |
| 2 | Timers + Keep Awake + System Metrics + Audio + Quick Actions | Not Started |
| 3 | Music + Calendar + Context Resolution | Not Started |
| 4 | File Shelf + Clipboard | Not Started |
| 5 | Claude Code + Codex + generic developer activity protocol | Not Started |
| 6 | Profiles + Settings + Onboarding + Accessibility + Performance + QA | Not Started |

---

## Phase 0 — Repository Bootstrap

**Status:** Complete

**Goals**
- A clean repository connected to GitHub, safe for multiple coding agents to work in.

**Major Deliverables**
- Git repository on `main`, connected to `origin`.
- Agent, product, architecture, roadmap, development, contribution, privacy and security documentation.
- `.gitignore`, `.editorconfig`, GitHub issue/PR templates.
- Minimal SwiftUI macOS app that builds, launches and has a passing smoke test.
- `Scripts/bootstrap.sh` environment diagnostics.

**Dependencies**
- None.

**Completion Criteria**
- Project builds (Debug and Release) and tests pass.
- Documentation present; no credentials or build products committed.
- Initial commit pushed to GitHub.

---

## Phase 1 — Notch Foundation + Activity Engine + State Machine

**Status:** In Review — implemented on `feature/phase-1-foundation`; complete once merged to `main`.

Verification so far: 65 unit tests pass; panel geometry checked on a notched built-in display and an external non-notched display (virtual notch); Idle → Live → Peek → Expanded → Collapse, Shelf, attention auto-peek, interruption and restoration exercised via the debug panel; idle CPU 0%, 0 wakeups. Not yet manually verified: full-screen apps / Spaces switching, real file drag over the notch, display hot-plug, Launch at Login from `/Applications`.

**Goals**
- Establish the notch surface and the core pipeline every later feature depends on.

**Major Deliverables**
- Background / menu-bar utility lifecycle; Launch at Login infrastructure; basic settings infrastructure.
- Notch geometry detection and a transparent, borderless notch panel (with defined behavior on non-notched displays, multiple displays, Spaces and full-screen apps).
- `NotchActivity` model, `ActivityStore`, activity resolver, priority levels, expiry, queueing, interruption and restoration.
- `NotchStateMachine` covering Idle, Live Activity, Peek, Expanded and Shelf; hover, click, outside-click dismissal and basic drag detection.
- Minimal presentation for each state with interruptible spring animations.
- Developer-only debug panel generating fake Music, Meeting, Timer, File Transfer, Agent Attention and Clipboard activities.
- Unit tests for store, resolver and state machine.
- ADRs for notch window strategy and the activity engine.
- Finalized toolchain requirements in `DEVELOPMENT.md` (deployment target, Xcode version, signing, sandbox).

**Dependencies**
- Phase 0.

**Completion Criteria**
- Every state can be simulated from the debug panel: Idle → Live Activity → Peek → Expanded → Collapse.
- Activities interrupt each other by priority, and the previous activity returns when a higher-priority one disappears.
- State machine transitions are fully unit tested.
- Idle CPU usage is negligible.

---

## Phase 2 — Timers + Keep Awake + System Metrics + Audio + Quick Actions

**Status:** Not Started

**Goals**
- Ship the first real activity providers using only local system APIs.

**Major Deliverables**
- Timer feature.
- Keep Awake (power assertions).
- CPU / memory / memory pressure, battery and charging state.
- Audio output / volume controls.
- Quick Actions.

**Dependencies**
- Phase 1 Activity Engine and State Machine.

**Completion Criteria**
- Without connecting any account, NotchDeck is a useful notch utility.
- Each feature publishes activities exclusively through the Activity Engine.
- Each feature can be individually disabled in settings.
- Metrics sampling is efficient and pauses when not visible.
- Tests cover feature state logic.

---

## Phase 3 — Music + Calendar + Context Resolution

**Status:** Not Started

**Goals**
- Surface media and meetings, and make the resolver context-aware.

**Major Deliverables**
- Now Playing display and playback controls (via supported APIs; limitations documented).
- Calendar integration via EventKit with contextual permission requests.
- Context resolution: choosing between competing activities (e.g. meeting starting vs. music playing).

**Dependencies**
- Phase 1; Phase 2 patterns for providers.

**Completion Criteria**
- Competing activities resolve predictably and are covered by tests.
- Calendar permission is requested only when the user enables the feature.

---

## Phase 4 — File Shelf + Clipboard

**Status:** Not Started

**Goals**
- Provide a temporary holding area for files and clipboard items.

**Major Deliverables**
- File Shelf with drag-and-drop in and out.
- Clipboard history stored locally, with clear retention controls.

**Dependencies**
- Phase 1 Shelf state.

**Completion Criteria**
- Clipboard contents never logged or transmitted.
- Shelf handles file references safely (validation, missing files).

---

## Phase 5 — Claude Code + Codex + Generic Developer Activity Protocol

**Status:** Not Started

**Goals**
- Let developer tools report activity to NotchDeck securely.

**Major Deliverables**
- A documented, versioned generic developer activity protocol (`DeveloperActivityProvider`).
- `notchctl` command-line bridge with JSON input.
- Secure, local, authenticated IPC (no unauthenticated network listener).
- Claude Code and Codex integrations built on that protocol.
- ADR for agent IPC.

**Dependencies**
- Phase 1 Activity Engine; priority levels including Attention Required.

**Completion Criteria**
- External tools can publish activities only through the authenticated local channel.
- Malformed input is rejected safely and covered by tests.

---

## Phase 6 — Profiles + Settings + Onboarding + Accessibility + Performance + QA

**Status:** Not Started

**Goals**
- Make NotchDeck polished, configurable and release-ready.

**Major Deliverables**
- Profiles and a Settings window.
- First-run onboarding with contextual permission explanations.
- Accessibility review (VoiceOver, Reduce Motion, contrast, keyboard access).
- Performance and energy profiling; regression budget.
- QA pass and release configuration.

**Dependencies**
- Phases 1–5.

**Completion Criteria**
- Accessibility and performance targets documented and met.
- Release build signed and verified.
