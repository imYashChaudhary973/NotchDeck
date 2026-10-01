# Product

## Product

```text
NotchDeck
```

## One-Sentence Description

A native macOS command center that turns the MacBook notch into a contextual surface for live activities, controls, files, meetings, timers and developer workflows.

## The Problem

The MacBook notch occupies prime screen real estate at the top-center of the display — the place the eye naturally returns to — yet it shows nothing. Meanwhile, the things a user wants to glance at (what's playing, when the next meeting starts, whether a timer is done, whether a coding agent needs input) are scattered across the menu bar, notifications, Dock badges and background windows.

NotchDeck uses the notch as a single, calm, contextual surface for that information.

## Target Users

- MacBook users with a notched display who want glanceable status without switching windows.
- Developers who run long-lived tools (builds, Claude Code, Codex) and want to know when attention is required.
- People who live in their calendar, music and timers throughout the day.

On Macs without a notch, NotchDeck may provide an equivalent top-center surface; the exact behavior is decided in Phase 1.

## Product Principles

### Context over clutter

Do not display everything simultaneously. At any moment, NotchDeck shows the most relevant activity — not every activity. Many features can exist; few should be visible at once.

### Progressive disclosure

Information is revealed in layers, from least to most intrusive:

```text
Idle            The notch looks like a notch. Nothing competes for attention.
Live Activity   A compact indicator alongside the notch (e.g. timer countdown, playing track).
Peek            A brief, slightly expanded view triggered by an event or hover.
Expanded        A full panel with controls and details, opened deliberately by the user.
Shelf           A drop target / holding area for files and clipboard items.
```

Each layer should be useful on its own; users should never be forced into a deeper layer to get basic information.

### Native experience

The app should look and behave like something that belongs on macOS: system materials, system typography, standard animations and accessibility behavior, respect for Reduce Motion, Dark/Light mode and multiple displays.

### Extremely low friction

Important information should require little or no navigation. Common actions (pause music, join meeting, stop timer) should be one interaction away.

### User-controlled automation

Users decide which integrations may surface automatically, and how intrusively. An integration that is allowed to show a Live Activity is not automatically allowed to expand the notch.

### Privacy first

Local information stays local unless a feature explicitly requires otherwise and the user has understood that. See [`PRIVACY.md`](PRIVACY.md).

## Planned Capabilities

None of these exist yet. See [`ROADMAP.md`](ROADMAP.md) for sequencing.

| Area | Examples |
| --- | --- |
| Productivity | Timers, Keep Awake, Quick Actions |
| System | CPU / memory metrics, audio output and volume |
| Media | Now Playing and playback controls |
| Calendar | Upcoming and in-progress meetings, join links |
| Files | File Shelf (drag-and-drop holding area), clipboard history |
| Developer | Claude Code activity, Codex activity, a generic developer activity protocol |
| Personalization | Profiles, settings, onboarding |

## Non-Goals

- A general-purpose menu bar replacement.
- A cloud service or account system.
- Showing everything at once.
- Depending on private Apple APIs for core functionality.
