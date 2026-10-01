# NotchDeck — Six-Phase Engineering Plan

> **How to use this document.** This is the source brief for every development phase. Each phase section ends with a *Coding Agent Prompt* — when a phase is started, that prompt is the task description, interpreted together with [`AGENTS.md`](../../AGENTS.md), [`ARCHITECTURE.md`](../../ARCHITECTURE.md) and [`ROADMAP.md`](../../ROADMAP.md).
>
> The plan was written before the repository existed ("NotchApp" refers to NotchDeck). Where it conflicts with repository rules, the repository rules win:
>
> - **Developer bridge transport.** The plan lists "Unix socket/local HTTP/CLI bridge". Per [`SECURITY.md`](../../SECURITY.md), NotchDeck never exposes an unauthenticated listener; prefer XPC or a permission-restricted Unix domain socket. Any HTTP transport would have to be loopback-only *and* authenticated, and needs an ADR.
> - **Presentation states.** The Phase 1 prompt says "four presentation states" but lists five; there are five (idle, liveActivity, peek, expanded, shelf).
> - **Repository structure.** The source tree lives in `NotchDeck/` (not `NotchApp/`), and tests live in the separate `NotchDeckTests/` target.
>
> The plan text below is preserved as originally written.

---

# macOS Notch Command Center
## Full 6-Phase Engineering Plan

### Product principle

The application should **not** be built as 20 independent notch widgets.

Build one central system:

**Events → Activity Engine → Priority Resolver → Notch State → UI**

Examples:

```text
Spotify starts playing
        ↓
MusicProvider
        ↓
NotchActivityEngine
        ↓
Priority Resolver
        ↓
Compact Music Activity
```

```text
Meeting starts in 3 minutes
        ↓
CalendarProvider
        ↓
Higher Priority
        ↓
Music collapses
        ↓
Meeting Activity takes over
```

```text
Claude Code needs input
        ↓
AgentProvider
        ↓
Critical Activity
        ↓
Notch displays "Claude needs you"
```

This architecture is what will stop the application from becoming cluttered.

---

# Recommended Technical Foundation

Use:

- Swift
- SwiftUI for most UI
- AppKit where SwiftUI is insufficient
- `NSPanel` / custom borderless window for notch surfaces
- Observation / Combine-style reactive state
- EventKit for Calendar
- CoreAudio for volume/audio devices
- IOKit/Mach APIs for system metrics where supported
- NSPasteboard for clipboard
- NSItemProvider / drag-and-drop APIs
- File-system event monitoring for file changes
- UserNotifications for optional fallback notifications
- ServiceManagement for Launch at Login
- Keychain for sensitive tokens
- JSON/config-based integration protocol
- Unix socket/local HTTP/CLI bridge for developer integrations

Avoid private macOS frameworks for the core product.

Some macOS controls such as generic system-wide media metadata, brightness, Focus mode, Wi-Fi/Bluetooth toggling and browser download progress can be difficult or unavailable through stable public APIs.

Design integrations as capability-based providers instead:

```text
Capability available
→ show native control

Capability unavailable
→ show status / open relevant settings / use supported provider

Never
→ depend on fragile private APIs for core functionality
```

---

# Suggested Repository Structure

```text
NotchApp/
│
├── App/
│   ├── NotchApp.swift
│   ├── AppDelegate.swift
│   └── AppEnvironment.swift
│
├── Core/
│   ├── Activities/
│   │   ├── Activity.swift
│   │   ├── ActivityType.swift
│   │   ├── ActivityPriority.swift
│   │   ├── ActivityStore.swift
│   │   └── ActivityResolver.swift
│   │
│   ├── Notch/
│   │   ├── NotchController.swift
│   │   ├── NotchWindow.swift
│   │   ├── NotchGeometry.swift
│   │   ├── NotchState.swift
│   │   └── NotchStateMachine.swift
│   │
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
│   ├── AppleMusic/
│   ├── Spotify/
│   ├── ClaudeCode/
│   ├── Codex/
│   └── Calendar/
│
├── UI/
│   ├── Compact/
│   ├── Peek/
│   ├── Expanded/
│   ├── Shelf/
│   └── Components/
│
├── Services/
│
├── Settings/
│
└── Tests/
```

---

# Core Activity Model

Every feature should speak the same language.

Example:

```swift
struct NotchActivity: Identifiable {
    let id: UUID
    let source: ActivitySource
    let type: ActivityType
    let priority: ActivityPriority

    let title: String
    let subtitle: String?

    let startedAt: Date
    let expiresAt: Date?

    let progress: Double?

    let presentation: ActivityPresentation
    let actions: [ActivityAction]
}
```

Suggested priorities:

```text
10 Ambient
20 Passive
30 Active
40 Time Sensitive
50 Attention Required
60 Critical
```

Examples:

```text
CPU stats                10
Music                    20
Clipboard                20
Active timer             30
File transfer            30
Meeting in 15 minutes    30
Meeting in 3 minutes     40
Timer < 10 seconds       40
Agent completed          40
Agent needs input        50
Recording warning        50
```

---

# NOTCH STATES

Create these states once and let every feature use them.

### State 0 — Idle

Physical notch only.

Optional tiny indicators.

### State 1 — Live Activity

Small extension beside the notch.

Example:

```text
┌─────────────────────────────┐
│         NOTCH      12:42    │
└─────────────────────────────┘
```

or

```text
♫ Midnight City       ▶
```

### State 2 — Peek

Small hover/click expansion.

### State 3 — Expanded

Main command center.

### State 4 — Shelf

Large workspace used primarily for dragged content, clipboard items and richer interactions.

---

# PHASE 1 — Native Notch Foundation

## Goal

Build the foundation on which every other feature will depend.

Do **not** start with Spotify, Claude, Calendar, clipboard, etc.

First make the notch itself excellent.

## Build

- macOS app lifecycle
- menu-bar/background utility behavior
- Launch at Login
- detect current screen
- detect notched MacBook display
- calculate notch geometry
- multiple-display support
- non-notch fallback
- transparent notch window
- NSPanel behavior
- Spaces/full-screen behavior
- compact mode
- peek mode
- expanded mode
- shelf mode
- hover detection
- click detection
- outside-click dismissal
- basic drag detection
- animations
- Activity Engine
- priority resolver
- activity queue
- automatic activity expiry
- state machine

Build a developer debug panel allowing fake activities:

```text
Music
Meeting
Timer
Claude Waiting
Download
Clipboard
```

This will make future development dramatically faster.

## Phase 1 Definition of Done

The app should be able to simulate every major state even though integrations don't exist yet.

It must support:

```text
Idle
↓
Live Activity
↓
Peek
↓
Expanded
↓
Collapse
```

Activities must be able to interrupt each other according to priority.

## Coding Agent Prompt — Phase 1

You are building Phase 1 of a native macOS application that turns the MacBook notch into a contextual command center.

Read the existing repository completely before making architectural changes.

The application's most important architectural concept is a central Notch Activity Engine. Features must never directly control the notch window. Instead, features publish activities and the Activity Engine decides what should be presented.

Build the native application foundation using Swift, SwiftUI and AppKit where appropriate.

Implement:

1. macOS application lifecycle suitable for a primarily background/menu-bar utility.
2. Detection of the active Mac display.
3. Detection and geometry handling for MacBook displays containing a notch using supported macOS APIs.
4. Graceful behavior on external displays and Macs without a physical notch.
5. A transparent/borderless notch window or NSPanel correctly anchored around the notch.
6. Four presentation states:
   - idle
   - liveActivity
   - peek
   - expanded
   - shelf
7. A formal NotchStateMachine controlling transitions between these states.
8. Hover behavior.
9. Click-to-expand behavior.
10. Click-outside-to-collapse behavior.
11. Smooth interruptible spring-style animations.
12. Multi-display handling.
13. Proper macOS Spaces/full-screen behavior.
14. A reusable NotchActivity model.
15. Activity priority levels.
16. ActivityStore.
17. ActivityResolver.
18. Expiring activities.
19. Queued activities.
20. Priority-based activity interruption.
21. Restoration of the previous activity when a higher-priority temporary activity disappears.
22. A developer-only debug screen capable of generating fake Music, Meeting, Timer, File Transfer and Agent Attention activities.
23. Basic settings infrastructure.
24. Launch-at-login infrastructure.

Keep visual design minimal and native. Do not create a dashboard filled with generic cards.

Separate presentation, system services and feature providers cleanly.

Do not introduce third-party dependencies unless there is a strong architectural reason.

Do not use private macOS frameworks.

Add unit tests for the activity resolver and state machine.

Create or update:

- README.md
- ARCHITECTURE.md
- AGENTS.md

ARCHITECTURE.md must document the activity pipeline and explain how future features register activity providers.

Before finishing:
- build the project
- resolve compiler warnings caused by your work
- run tests
- verify state transitions
- verify notch window behavior on multiple display configurations where possible

Do not implement real music/calendar/agent integrations in this phase.

---

# PHASE 2 — Core Utility Features

## Goal

Make the application useful without requiring any external account.

Build the features that work entirely locally.

## Features

### Timer

Support:

```text
5 min
10 min
15 min
25 min
30 min
1 hour
Custom
```

Timer should become a Live Activity.

At important moments its priority changes.

Example:

```text
25:00    priority 30
01:00    priority 35
00:10    priority 40
Finished priority 50 temporarily
```

Support multiple timers internally, while showing only the most relevant one.

### Keep Awake

Use a supported system power assertion.

Options:

```text
30 minutes
1 hour
2 hours
Until disabled
```

Show a subtle notch indicator while active.

### System Performance

Collect:

- total CPU
- memory usage
- memory pressure
- battery
- charging state

Expanded mode can additionally show expensive processes where permitted.

Keep it lightweight.

Do not poll unnecessarily quickly.

### Audio

Support:

- current output volume
- mute
- output device
- volume adjustments

Scrolling over the notch can optionally adjust volume.

### Quick Actions

Implement actions such as:

```text
Start timer
Keep Awake
Open Downloads
Open Applications
Open Activity Monitor
Take Screenshot
Lock Screen
```

Only expose actions supported safely by public APIs.

## Phase 2 Definition of Done

Without connecting any account, the app should already function as a useful notch utility.

## Coding Agent Prompt — Phase 2

Continue the existing macOS Notch Command Center project.

Do not redesign or replace the Phase 1 architecture.

All new functionality must publish into the existing Notch Activity Engine rather than directly modifying notch UI.

Implement Phase 2: local utility features.

Build:

TIMER SYSTEM
- multiple timer model
- timer persistence where appropriate
- presets
- custom durations
- pause
- resume
- cancel
- timer completion
- Live Activity representation
- priority escalation as timer approaches zero
- completion activity
- compact timer presentation
- expanded timer controls

KEEP AWAKE
- implement using supported macOS power-management APIs
- presets for 30 minutes, 1 hour, 2 hours and indefinite
- automatically release assertions correctly
- restore state safely after restart
- clearly expose active status

SYSTEM METRICS
- CPU utilization
- memory utilization
- memory pressure where supported
- battery percentage
- charging state
- energy-conscious polling
- expanded system metrics presentation

AUDIO
- read system output volume using public APIs
- mute/unmute
- change volume
- enumerate supported output devices
- change output device where supported
- optionally support scroll-over-notch volume adjustment

QUICK ACTIONS
Create an extensible QuickAction protocol and initial supported actions.

Do not implement functionality using private APIs merely because a system control would be convenient.

If macOS does not expose a stable public API, represent the capability as unavailable or use a safe fallback such as opening the relevant System Settings pane.

Update settings so users can individually disable:
- timers
- system metrics
- audio controls
- keep awake
- quick actions

Add unit tests for timer behavior and provider/activity publication.

Profile CPU usage while idle. The notch utility should have extremely low idle overhead.

Run the app and tests before completing the phase.

Document newly added providers in ARCHITECTURE.md.

---

# PHASE 3 — Music + Calendar + Contextual Activities

## Goal

Turn the notch into something that responds intelligently to the user's day.

## Music

Create a provider architecture instead of hardcoding one media service.

Start with supported integrations such as:

```text
Apple Music
Spotify
```

Potential presentation:

```text
┌─────────────────────────────┐
│ artwork  Midnight City  ▶︎  │
└─────────────────────────────┘
```

Expanded:

```text
[ artwork ]

Midnight City
M83

━━━━━━●━━━━━━
2:14          4:03

◀︎        ▶︎        ▶︎

Volume ━━━━━●━━
```

Generic system-wide media detection should not become a dependency if it requires private APIs.

### Calendar

Use EventKit.

Permission flow must be clean.

Show:

```text
Design Review
11:00
Starts in 12 min
```

Then:

```text
Design Review
Starting now
[Join]
```

Expanded view:

```text
10:00 Standup
11:00 Design Review
14:30 Alex
17:00 Project Review
```

Support meeting URL detection from event information.

### Context rules

Example:

```text
Music playing:
Music priority 20

Meeting 15 min away:
Calendar priority 30

Meeting 3 min away:
Calendar priority 40

Meeting starting:
Calendar priority 50

After meeting notification:
Music automatically returns.
```

## Coding Agent Prompt — Phase 3

Implement Phase 3 of the existing native macOS Notch Command Center.

Preserve the existing Activity Engine and provider architecture.

The goal of this phase is contextual activities using Music and Calendar.

CALENDAR

Use Apple's supported EventKit APIs.

Implement:
- permission request
- permission states
- calendar selection
- upcoming-event query
- configurable look-ahead interval
- event start/end monitoring
- meeting URL extraction
- Join Meeting action
- compact upcoming meeting activity
- meeting-starting activity
- expanded schedule
- automatic expiration after relevant time passes

Do not continuously query EventKit unnecessarily.

Use intelligent refresh scheduling based on the next event.

Create configurable rules such as:
- upcoming event
- event within 15 minutes
- event within 5 minutes
- event starting now

Change activity priority appropriately.

MUSIC

Create a MediaProvider abstraction.

Do not make the rest of the application dependent on a specific music service.

Implement supported providers for Apple Music and Spotify where stable public/supported integration mechanisms are available.

Support where available:
- title
- artist
- album
- artwork
- playback status
- play
- pause
- previous
- next
- progress
- duration

Do not use private MediaRemote frameworks.

If a capability cannot be implemented cleanly with supported APIs, design the provider so that capability is marked unsupported.

Build:
- compact music Live Activity
- expanded music interface
- artwork transitions
- track change animations
- play/pause controls

CONTEXT RESOLUTION

Ensure Calendar can temporarily interrupt Music.

Example:

Music playing
→ meeting becomes imminent
→ meeting takes notch priority
→ meeting activity expires
→ music automatically returns.

Add tests for this behavior.

Do not redesign unrelated screens.

Update ARCHITECTURE.md documenting MediaProvider and CalendarProvider.

Run tests and verify permission-denied behavior before completing.

---

# PHASE 4 — File Shelf + Clipboard

## Goal

Create one of the product's defining interactions:

**drag something toward the notch and the notch physically opens to accept it.**

## File Shelf

Accept:

- files
- folders
- images
- screenshots
- browser images
- URLs
- text
- PDFs

Interaction:

```text
User starts dragging
        ↓
Cursor approaches notch
        ↓
Notch expands
        ↓
"Drop Here"
        ↓
Item lands in Shelf
```

Shelf:

```text
┌───────────────────────────────────────┐
│           NOTCH SHELF                 │
│                                       │
│ [image] [PDF] [URL] [Screenshot]      │
│                                       │
└───────────────────────────────────────┘
```

User can later drag any object back out.

Items should be temporary by default.

Options:

```text
Keep 1 hour
Keep today
Pin
Delete
Reveal in Finder
Copy
Share
```

### Clipboard History

Monitor pasteboard change count.

Store:

```text
Text
URLs
Images
Colors
Code
File references
```

Provide search.

Sensitive data handling matters.

Allow applications to be excluded from clipboard capture.

Provide:

```text
Clear History
Pause Clipboard
Maximum History Size
```

Never sync clipboard history remotely by default.

## Coding Agent Prompt — Phase 4

Implement Phase 4: Notch Shelf and Clipboard.

This interaction should feel like a native extension of macOS drag and drop.

Do not bypass the existing notch state machine.

FILE SHELF

Implement a Shelf domain model supporting:
- files
- folders
- images
- URLs
- text
- file promises where practical

Implement drag detection around the notch.

When a compatible drag enters the configured notch activation region:
- transition into Shelf state
- visually indicate a valid drop target

When dropped:
- safely resolve the item
- create a ShelfItem
- display an appropriate preview

Users must be able to drag ShelfItems back into Finder and other applications.

Implement:
- temporary items
- pinned items
- item expiration
- delete
- reveal in Finder
- copy
- Quick Look where appropriate
- share via supported system Share services

Do not duplicate large files unnecessarily. Prefer security-scoped references/bookmarks or appropriate temporary storage strategies.

CLIPBOARD

Use NSPasteboard.

Monitor pasteboard changes efficiently.

Support:
- plain text
- rich text metadata where sensible
- URLs
- images
- file URLs
- recognized color strings where useful

Implement:
- clipboard history
- search
- pinning
- delete
- clear history
- pause monitoring
- maximum history limit
- excluded applications/preferences where technically possible

Treat privacy as a first-class concern.

Do not send clipboard content to any server.

Do not log clipboard contents to console or analytics.

Persist only what the product actually needs.

Create tests for:
- Shelf item lifecycle
- expiration
- pinning
- clipboard deduplication
- history limits

Optimize image thumbnails instead of loading full-resolution assets everywhere.

Update ARCHITECTURE.md and privacy documentation.

---

# PHASE 5 — Claude Code, Codex + Developer Activity System

## Goal

Make the notch uniquely valuable to developers.

Do not scrape terminal UI.

Create an actual integration protocol.

## Local Integration Bridge

Create something like:

```bash
notchctl activity start \
  --app claude \
  --project Rove \
  --title "Implementing tabs"

notchctl activity waiting \
  --app claude \
  --project Rove \
  --message "Permission required"

notchctl activity complete \
  --app claude \
  --project Rove
```

Internally:

```text
Claude/Codex Hook
      ↓
notchctl
      ↓
Local IPC
      ↓
AgentIntegrationService
      ↓
Activity Engine
```

Possible statuses:

```text
Starting
Thinking
Working
Running command
Waiting
Needs permission
Needs user input
Completed
Failed
```

Compact states:

```text
Claude • Working
```

```text
Claude needs you
```

```text
✓ Codex finished
```

Expanded:

```text
Claude Code

Rove
Implement tab management

● Working
12m 48s

[Open Terminal]
```

### Multiple agents

Support:

```text
Claude — Rove
Codex — ZenVoice
Claude — NotchApp
```

The notch shows the most important one.

Expanded view shows all running agents.

### Generic protocol

Do not make this Claude/Codex-specific.

Create a generic:

```text
DeveloperActivityProvider
```

Then any future tool can integrate.

## Coding Agent Prompt — Phase 5

Implement Phase 5 of the Notch Command Center: Developer Agent Integrations.

This is a core differentiating feature.

Do NOT implement terminal-screen scraping.

Create a generic local developer activity protocol that Claude Code, Codex and future coding tools can publish into.

ARCHITECTURE

Create a DeveloperActivity model including:

- integration ID
- provider name
- project
- workspace path
- session ID
- task
- status
- status message
- startedAt
- updatedAt
- optional progress
- optional terminal/app deep-link information

Statuses should include:

- starting
- working
- runningCommand
- waiting
- needsInput
- needsPermission
- completed
- failed
- cancelled

LOCAL BRIDGE

Create a lightweight command-line utility named `notchctl`.

Example usage:

notchctl agent start
notchctl agent update
notchctl agent waiting
notchctl agent complete
notchctl agent fail

Use secure local IPC between notchctl and the macOS app.

Prefer a Unix domain socket, XPC or another appropriate local-only architecture.

Do not expose an unauthenticated network server.

Create clear machine-readable JSON input support.

Example conceptual event:

{
  "provider": "claude-code",
  "project": "Rove",
  "status": "needsInput",
  "message": "Claude requires approval",
  "workspace": "/Users/.../Rove"
}

INTEGRATIONS

Create adapters for Claude Code and Codex using supported hooks/configuration mechanisms where available.

Keep those adapters outside the generic core.

Where hooks differ between versions, isolate version-specific behavior.

Provide setup documentation rather than adding brittle parsing.

UI

Compact activities:

Working:
Claude · Rove

Attention:
Claude needs you

Completed:
Rove finished ✓

Expanded developer view should show all active sessions with:
- provider
- project
- current task
- status
- elapsed duration

Actions:
- open workspace
- open Terminal
- dismiss completed activity

PRIORITY

Working agent:
low/moderate priority.

Completed:
temporary moderate activity.

Needs input:
high priority.

Needs permission:
high priority.

Failed:
high priority.

Multiple agents must coexist correctly.

Do not let an ordinary working agent override an imminent calendar event.

Add unit tests for multi-agent priority behavior and activity lifecycle.

Update README.md with integration setup examples.

Update ARCHITECTURE.md with the generic developer event protocol.

---

# PHASE 6 — Command Center, Personalization + Production Polish

## Goal

Turn all the independent systems into one cohesive product.

This phase determines whether the app feels premium or like a collection of features.

## Expanded Command Center

Do not show every integration simultaneously.

Make the expanded area contextual.

Example while coding:

```text
┌─────────────────────────────────────────┐
│                                         │
│              Mac Notch                  │
│                                         │
│ Claude Code                 ● Working   │
│ Rove                         08:42      │
│                                         │
│ ♫ Midnight City                  ▶︎     │
│                                         │
│ Design Review                in 18 min  │
│                                         │
│ CPU 22%        Memory 61%               │
│                                         │
│ Timer                           18:41    │
│                                         │
└─────────────────────────────────────────┘
```

A normal user might instead see:

```text
Music
Meeting
Timer
Clipboard
```

The interface adapts according to enabled providers.

---

# Focus Profiles

Add profiles:

```text
Normal
Coding
Study
Meeting
Presentation
```

Example:

### Coding

Enable/promote:

```text
Claude
Codex
Timer
Music
CPU
Calendar
```

### Meeting

Enable/promote:

```text
Calendar
Microphone status
Timer
Keep Awake
```

### Presentation

Enable:

```text
Keep Awake
Battery
Timer
```

Hide distracting content.

---

# Settings

Categories:

```text
General
Notch
Activities
Music
Calendar
Timers
Shelf
Clipboard
Developer
System
Privacy
Advanced
```

Allow users to choose:

```text
Enabled providers
Provider priorities
Hover behavior
Animation intensity
Launch at Login
Shelf retention
Clipboard limits
Calendar selection
Agent integrations
Scroll gestures
Compact content
```

---

# Gestures

Add only after core interactions work reliably.

Potential interactions:

```text
Click notch
→ expand

Hover
→ peek

Drag file
→ shelf

Scroll
→ volume

Right-click
→ actions

Swipe
→ next active activity
```

Every gesture should have a normal clickable equivalent.

---

# Permissions UX

Request permissions only when required.

For example:

```text
User enables Calendar
→ ask for Calendar permission

User never enables Calendar
→ never ask
```

Do not present five permission dialogs during onboarding.

---

# Onboarding

Keep onboarding extremely short.

### Screen 1

```text
Your Mac's new control center.
```

### Screen 2

Choose:

```text
Music
Calendar
Timers
Clipboard
Developer Tools
System
```

### Screen 3

```text
Move your pointer to the notch.
```

Then demonstrate expansion.

Done.

---

# Performance Requirements

This is a utility expected to run all day.

Set strict targets.

Optimize:

- idle CPU
- memory
- wakeups
- polling
- timers
- animations
- thumbnail caches
- filesystem observers

Providers should be event-driven whenever possible.

Don't query CPU, Calendar, audio, clipboard and agent states every few milliseconds.

---

# Accessibility

Support:

- Reduce Motion
- VoiceOver
- keyboard navigation
- sufficient contrast
- larger system text where practical
- no essential information communicated exclusively through color

---

# Reliability

Test:

```text
Sleep/wake
Display connect/disconnect
External monitors
MacBook lid changes
Fullscreen apps
Spaces
Mission Control
App restart
Crash recovery
Calendar permission revoked
Clipboard permission/state changes
Agent disappears unexpectedly
Timer during sleep
Audio device disconnect
Multiple simultaneous activities
```

---

# Coding Agent Prompt — Phase 6

Complete Phase 6 of the existing macOS Notch Command Center.

This phase is about integration, polish, performance and production readiness rather than adding random new features.

Build the unified expanded Command Center.

It must be generated from enabled Activity Providers rather than a hardcoded dashboard.

Implement Focus Profiles:

- Normal
- Coding
- Study
- Meeting
- Presentation

Profiles should influence which activity types are visible and their effective priority.

Implement comprehensive settings for:

- launch behavior
- notch behavior
- enabled providers
- priority preferences
- music
- calendar
- timers
- shelf
- clipboard
- developer integrations
- system monitoring
- privacy
- animations
- gestures

Build a short first-run onboarding flow.

Permissions must be requested contextually, not all at startup.

Add support for:
- Reduce Motion
- keyboard navigation
- VoiceOver labels
- light mode
- dark mode

Polish all state transitions:

idle
→ live activity
→ peek
→ expanded
→ shelf

Transitions must be interruptible and must not produce inconsistent state when multiple events arrive rapidly.

Add contextual gestures where they do not interfere with normal macOS interactions.

Perform a performance audit.

Measure:
- idle CPU
- idle memory
- wakeups
- system metric polling
- Calendar refresh behavior
- clipboard monitoring
- animation overhead

Remove unnecessary timers and polling.

Test:
- sleep/wake
- monitor connect/disconnect
- Spaces
- fullscreen applications
- multiple displays
- application relaunch
- denied permissions
- revoked permissions
- rapid activity creation
- multiple simultaneous agent sessions
- multiple timers
- active meeting + music + agent notification
- clipboard containing large images
- Shelf containing large files

Do not solve unsupported macOS capabilities using private frameworks.

Audit the repository architecture and remove duplicated feature logic.

Update:
- README.md
- ARCHITECTURE.md
- PRODUCT.md
- AGENTS.md
- PRIVACY.md

Create a final QA checklist.

Build the project cleanly and run the full test suite.

Do not consider the phase complete while known crashes, state-machine bugs, permission-loop bugs or major memory leaks remain.

---

# FINAL PRODUCT ARCHITECTURE

The completed system should look conceptually like this:

```text
                  ┌────────────────────┐
                  │     macOS APIs     │
                  └─────────┬──────────┘
                            │
       ┌────────────────────┼────────────────────┐
       │                    │                    │
   Calendar              System              Clipboard
       │                    │                    │
       ├──── Music ─────────┼──── Timer ─────────┤
       │                    │                    │
       └──── Agents ────────┴──── Shelf ─────────┘
                            │
                   Activity Providers
                            │
                            ▼
                  ┌───────────────────┐
                  │   ActivityStore   │
                  └─────────┬─────────┘
                            │
                            ▼
                  ┌───────────────────┐
                  │ Priority Resolver │
                  └─────────┬─────────┘
                            │
                            ▼
                  ┌───────────────────┐
                  │ Notch StateMachine│
                  └─────────┬─────────┘
                            │
                            ▼
        ┌─────────────────────────────────────┐
        │                                     │
       Idle     Live     Peek     Expanded   Shelf
```

---

# DEVELOPMENT ORDER

Follow this exact dependency order:

**Phase 1 — Foundation**
Notch + Activity Engine + State Machine

↓

**Phase 2 — Native Utilities**
Timers + Keep Awake + Stats + Audio

↓

**Phase 3 — Daily Context**
Music + Calendar

↓

**Phase 4 — Productivity**
Shelf + Clipboard

↓

**Phase 5 — Developer Intelligence**
Claude Code + Codex + Generic Agent Protocol

↓

**Phase 6 — Productization**
Profiles + Settings + Onboarding + Performance + QA

---

# MVP CUT LINE

A genuinely releasable early beta can exist after **Phase 4**.

That version would already contain:

- native notch interface
- contextual activity engine
- music
- meetings
- timers
- keep awake
- CPU/memory
- volume
- file shelf
- clipboard

Phase 5 then gives the application its strongest developer-oriented differentiator.

Phase 6 turns it into a polished production product.

---

# One Rule For Every Coding Agent

Put this near the top of `AGENTS.md`:

> Features do not own the notch. Features publish activities. The Activity Engine owns what the user sees.

That single rule will prevent most architectural problems as the app grows.
