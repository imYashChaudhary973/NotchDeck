# NotchDeck

A native macOS command center built around the MacBook notch.

> **🚧 Currently being built.** The notch foundation (Phase 1) and the local utilities (Phase 2: timers, Keep Awake, system metrics, audio, quick actions) are complete. Now Playing (Music, Spotify) and Calendar (Phase 3) are complete. The File Shelf and clipboard history (Phase 4) and the developer agent integrations — Claude Code, Codex and any tool through `notchctl` (Phase 5) — are implemented and in review.

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
| 1 — Notch foundation + Activity Engine + State Machine | Complete |
| 2 — Timers + Keep Awake + System Metrics + Audio + Quick Actions | Complete |
| 3 — Music + Calendar + Context Resolution | Complete |
| 4 — File Shelf + Clipboard | In Review |
| 5–6 | Not Started |

## Requirements

- macOS 14 Sonoma or later (a notched MacBook is ideal; other displays get a virtual notch)
- Xcode 16 or later to open the project (verified with Xcode 27.0)
- No third-party dependencies

## Developer Agents (Claude Code, Codex, any tool)

Coding agents and scripts report their sessions to NotchDeck with `notchctl`, over a local socket only your user account can reach. The notch shows "Claude · Rove" while an agent works, "Claude needs you" when it waits for your approval, and "Rove finished" when it is done; the command center lists every session. Nothing reads your terminal, and prompts and commands aren't forwarded.

**1. Install `notchctl`**, which ships inside the app (Settings ▸ Developer Agents shows the exact path and a command to copy):

```bash
ln -sf /Applications/NotchDeck.app/Contents/MacOS/notchctl /usr/local/bin/notchctl
notchctl ping   # NotchDeck is listening.
```

**2. Claude Code:** add these hooks to `~/.claude/settings.json` (merge them into an existing `hooks` object). Details, what each event shows and troubleshooting: [`docs/integrations/claude-code.md`](docs/integrations/claude-code.md).

```json
{
  "hooks": {
    "UserPromptSubmit":   [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code", "timeout": 5 }] }],
    "PreToolUse":         [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code", "timeout": 5 }] }],
    "PermissionRequest":  [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code", "timeout": 5 }] }],
    "PostToolUse":        [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code", "timeout": 5 }] }],
    "PostToolUseFailure": [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code", "timeout": 5 }] }],
    "Notification":       [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code", "timeout": 5 }] }],
    "Elicitation":        [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code", "timeout": 5 }] }],
    "ElicitationResult":  [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code", "timeout": 5 }] }],
    "PreCompact":         [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code", "timeout": 5 }] }],
    "Stop":               [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code", "timeout": 5 }] }],
    "StopFailure":        [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code", "timeout": 5 }] }],
    "SessionEnd":         [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code" }] }]
  }
}
```

**3. Codex:** add the same kind of hooks to `~/.codex/hooks.json`, running `notchctl hook codex`, and trust them in `/hooks` — see [`docs/integrations/codex.md`](docs/integrations/codex.md). Older Codex versions without hooks can report finished turns through `notify` in `~/.codex/config.toml`:

```toml
notify = ["notchctl", "hook", "codex-notify"]
```

**4. Any other tool** calls `notchctl agent` directly:

```bash
notchctl agent start    --provider my-tool --task "Implement tab management"
notchctl agent waiting  --provider my-tool --message "Waiting for CI"
notchctl agent permission --provider my-tool --message "Approve deploying to staging"
notchctl agent complete --provider my-tool
```

Raw JSON works too (`notchctl send '{"provider":"my-tool","status":"working"}'`). The protocol, every option and the exit codes are in [`docs/developer-activity-protocol.md`](docs/developer-activity-protocol.md). Developer agents can be turned off in Settings ▸ Features; while off, nothing listens.

## Development

```bash
git clone https://github.com/imYashChaudhary973/NotchDeck.git
cd NotchDeck
Scripts/bootstrap.sh       # environment diagnostics
open NotchDeck.xcodeproj   # or build/test from the command line:
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck test
```

NotchDeck runs as a menu-bar app (no Dock icon). In Debug builds, the menu bar item has **Debug Activities…**, which simulates music, meetings, timers, downloads, agent attention and clipboard activities. To open it at launch:

```bash
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/NotchDeck.app --args -NotchDeckShowDebugPanel YES
```

Hover the notch to peek, click it to expand, click elsewhere to collapse.

Full instructions: [`DEVELOPMENT.md`](DEVELOPMENT.md). Coding agents must read [`AGENTS.md`](AGENTS.md) first.

## Documentation

- [`PRODUCT.md`](PRODUCT.md) — product definition and principles
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — planned architecture and ADR process
- [`ROADMAP.md`](ROADMAP.md) — phases and status
- [`DEVELOPMENT.md`](DEVELOPMENT.md) — build, run, test
- [`docs/developer-activity-protocol.md`](docs/developer-activity-protocol.md) — the developer activity protocol and `notchctl`
- [`docs/integrations/`](docs/integrations/) — Claude Code and Codex setup
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — contribution guidelines
- [`AGENTS.md`](AGENTS.md) — rules for coding agents
- [`CHANGELOG.md`](CHANGELOG.md) — notable changes

## Privacy

NotchDeck is designed to keep your data on your Mac. See [`PRIVACY.md`](PRIVACY.md) and [`SECURITY.md`](SECURITY.md).

## License

License selection pending. Until a license is added, no rights are granted to use, copy, modify or distribute this code beyond what GitHub's Terms of Service allow.
