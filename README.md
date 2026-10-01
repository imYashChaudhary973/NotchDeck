# NotchDeck

A native macOS command center built around the MacBook notch.

> **🚧 Currently being built.** NotchDeck is in early development. The repository is bootstrapped (Phase 0) but none of the features below exist yet.

## Overview

The MacBook notch sits at the top-center of the screen — the spot your eye keeps coming back to — and shows nothing. NotchDeck turns it into a calm, contextual surface for live activities, controls, files, meetings, timers and developer workflows, showing only what matters right now.

## Planned Features

- **Live activities** — timers, now playing, upcoming meetings
- **System** — Keep Awake, CPU / memory, audio controls, quick actions
- **Shelf** — temporary file shelf and local clipboard history
- **Developer** — Claude Code and Codex activity, plus a generic protocol for other tools

See [`ROADMAP.md`](ROADMAP.md) for sequencing.

## Architecture

Features don't own the notch. They publish *activities*; a central Activity Engine resolves priority and drives a state machine that decides what is shown:

```text
Provider → NotchActivity → ActivityStore → Resolver → NotchStateMachine → Presentation
```

Details in [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Development Status

| Phase | Status |
| --- | --- |
| 0 — Repository bootstrap | Complete |
| 1 — Notch foundation + Activity Engine + State Machine | Not Started |
| 2–6 | Not Started |

## Requirements

- A Mac running macOS (minimum supported version **TBD during Phase 1**)
- Xcode 16 or later to open the project (verified with Xcode 27.0)
- No third-party dependencies

## Development

```bash
git clone https://github.com/imYashChaudhary973/NotchDeck.git
cd NotchDeck
Scripts/bootstrap.sh       # environment diagnostics
open NotchDeck.xcodeproj   # or build/test from the command line:
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck test
```

Full instructions: [`DEVELOPMENT.md`](DEVELOPMENT.md). Coding agents must read [`AGENTS.md`](AGENTS.md) first.

## Documentation

- [`PRODUCT.md`](PRODUCT.md) — product definition and principles
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — planned architecture and ADR process
- [`ROADMAP.md`](ROADMAP.md) — phases and status
- [`DEVELOPMENT.md`](DEVELOPMENT.md) — build, run, test
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — contribution guidelines
- [`AGENTS.md`](AGENTS.md) — rules for coding agents
- [`CHANGELOG.md`](CHANGELOG.md) — notable changes

## Privacy

NotchDeck is designed to keep your data on your Mac. See [`PRIVACY.md`](PRIVACY.md) and [`SECURITY.md`](SECURITY.md).

## License

License selection pending. Until a license is added, no rights are granted to use, copy, modify or distribute this code beyond what GitHub's Terms of Service allow.
