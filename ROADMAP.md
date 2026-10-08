# Roadmap

Development proceeds in numbered phases. When working on a phase, implement only that phase plus strictly necessary supporting work (see the Scope Rule in [`AGENTS.md`](AGENTS.md)).

The detailed brief for every phase — including its *Coding Agent Prompt* — is in [`docs/development/engineering-plan.md`](docs/development/engineering-plan.md). This file tracks status and completion criteria.

**MVP cut line:** a releasable early beta can exist after Phase 4. Phase 5 adds the developer differentiator; Phase 6 productizes.

| Phase | Title | Status |
| --- | --- | --- |
| 0 | Repository bootstrap | **Complete** |
| 1 | Notch foundation + Activity Engine + State Machine | **Complete** |
| 2 | Timers + Keep Awake + System Metrics + Audio + Quick Actions | **Complete** |
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

**Status:** Complete — merged to `main`.

Verification: 101 unit tests pass with no warnings; every notch state rendered off-screen and reviewed; panel geometry checked on notched built-in displays (220 × 38 pt, and 185 × 32 pt on a 14-inch M5 MacBook Pro; layer 27, flush with the top edge) and an external non-notched display (virtual notch); Idle → Live → Peek → Expanded → Collapse, Shelf, attention auto-peek, interruption and restoration exercised via the debug panel; idle CPU 0%, 0 wakeups. Full-screen behavior is defined and unit tested ([ADR 0001](docs/decisions/0001-notch-window-strategy.md)); drag descriptions are unit tested.

Manual checks (run 2026-10-08 with scripted input on a 14-inch M5 MacBook Pro, built-in display only). Items 2, 5 and 6 were verified only partly; the remaining parts are listed so they can be confirmed on real hardware:
- [x] Full-screen app on the notched display: the notch stays visible in the black band. Hover, click and outside-click dismissal also work over the full-screen app.
- [ ] Full-screen app on an external display with `Display: Primary display`: the virtual notch hides; *Claude Waiting* in the debug panel still peeks. *Partly verified on a simulated (virtual) display: the virtual notch moves to the primary display and hides under a full-screen window. Not yet verified: the attention peek over the covered display.*
- [x] Switching Spaces: the notch stays put on every Space (desktops and full-screen Spaces).
- [x] Dragging a real Finder file over the notch opens the Shelf; releasing returns the file to Finder.
- [ ] Connecting / disconnecting an external display and closing the lid move the notch to the right display. *Connect, disconnect and primary-display changes verified on a simulated display; closing the lid was approximated by mirroring the built-in display. Not yet verified: a real external display and a real lid close.*
- [ ] Launch at Login from a copy in `/Applications` (toggle in Settings, log out and back in). *The toggle registers the `/Applications` copy (Background Task Management: enabled, allowed). Not yet verified: relaunch after logging out and back in.*

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

**Status:** Complete — merged to `main`.

Verification (2026-10-08, 14-inch M5 MacBook Pro): 178 unit tests pass with no warnings (Debug and Release builds). In the running app with scripted input: starting a timer from Quick Actions shows the countdown Live Activity; Keep Awake holds a `PreventUserIdleDisplaySleep` assertion (`pmset -g assertions`), releases it on quit and restores it on relaunch; a running timer is restored after relaunch; the volume bar sets the system volume, and changes made elsewhere show up; scrolling over the notch (setting on) changes the volume and shows the HUD, which then returns the notch to the timer. Idle with every feature on: 0.0% CPU, 0 wake-ups. A visible countdown costs about 1% CPU; the open command center with live sampling about 1.5% ([ADR 0005](docs/decisions/0005-local-utility-providers.md)).

Still to check on real hardware:
- [ ] A timer reaching zero: the attention peek and the sound (covered by unit tests, not yet watched live).
- [ ] Output device switching with a second device (Bluetooth headphones, AirPlay or a display).
- [ ] The Charging peek when a charger is plugged in.
- [ ] Scroll-to-volume with a real trackpad and mouse wheel (scripted line scrolls verified).
- [ ] Each Settings ▸ Features toggle on and off while the app runs.

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

**Known constraint**
- macOS opens Mission Control's Spaces bar when a drag rests at the top edge of the screen for about a second (observed during Phase 1 checks, with or without NotchDeck). The Shelf's drop targets must be easy to reach before that happens.

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
