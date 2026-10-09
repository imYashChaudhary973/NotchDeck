# 0008. Developer Activity Bridge

- Status: Accepted
- Date: 2026-10-09

## Context

Phase 5 shows coding agents (Claude Code, Codex) and any other developer tool in the notch: one session per agent run, with its status (working, running a command, needs permission, finished…). The tools run in terminals and editors, outside NotchDeck, so they need a way to report to the app.

Constraints:

1. **Local IPC only** ([`SECURITY.md`](../../SECURITY.md)). No unauthenticated network listener on any interface, including `localhost`; peers must be authenticated; every message is untrusted input.
2. **Public APIs only** ([`AGENTS.md`](../../AGENTS.md)), and no terminal-screen scraping (Phase 5 brief).
3. **A generic protocol.** NotchDeck must not become Claude- or Codex-specific; any tool should be able to integrate without a change to the app. Tool-specific behavior that differs between versions has to be isolated.
4. **Low idle cost.** NotchDeck runs all day; listening must cost nothing while no tool reports.
5. **Hooks must never disturb the agent.** Claude Code and Codex run hooks synchronously in their agent loop; a slow, noisy or failing hook delays or changes the agent's behavior (for example, stdout of some hooks is added to the conversation, and exit code 2 blocks the action).
6. **Privacy** ([`PRIVACY.md`](../../PRIVACY.md)). Hook payloads contain prompts, commands, file contents and transcript paths, and the notch is visible on screen and in screen shares.

## Decision

### Transport: a Unix domain socket in a private directory

- NotchDeck listens on `~/Library/Application Support/NotchDeck/Bridge/bridge.sock`. The directory is created with mode `0700`; an existing one must be a real directory owned by the user (not a symlink), and its mode is reset to `0700`. The socket is `chmod`ed to `0600` after binding.
- Each accepted connection's peer user ID is read with `getpeereid`; a connection from any other user is closed unread.
- One exchange per connection: one JSON object of at most 16 KiB, ended by a newline or end of file, answered with one JSON response (`{"ok":true,"version":1}` or `{"ok":false,…,"error":…}`). Requests must arrive within 2 seconds; at most 8 connections are open at once.
- The listener (`DeveloperBridgeServer`, `DeveloperBridgeListener`) uses dispatch sources on a private queue: it wakes only when a client connects or sends data, and costs nothing while idle. It runs only while **Developer agents** is on in Settings (on by default); turning it off closes the socket and removes the file. A stale socket left by a crash is replaced; a socket that still answers (another NotchDeck) or a non-socket file at the path is left alone and reported in the command center with Retry.

### Schema: one versioned, validated message type

- `DeveloperBridgeMessage` (`Shared/DeveloperProtocol/`) is a `Codable` struct with `version` (1), `type` (`event`, `end`, `ping`), `provider`, `providerName`, `session`, `project`, `workspace`, `task`, `status`, `message`, `progress` and `terminal`. `validated()` enforces the limits and patterns (identifiers by character set and length, absolute workspace paths, progress in `0…1`), sanitizes and truncates free text, and rejects versions newer than the app's. Unknown keys are ignored, so optional keys can be added within a version.
- A session is identified by provider plus session ID, falling back to the workspace, then the project (`sessionKey`).
- The specification is [`docs/developer-activity-protocol.md`](../developer-activity-protocol.md).

### `notchctl`: the only client, bundled in the app

- `notchctl` is a command-line tool target embedded at `NotchDeck.app/Contents/MacOS/notchctl`; users link it onto their `PATH` (Settings shows the path and the command). It offers `agent <event>` (one subcommand per status), `send` (raw JSON), `hook <adapter>`, `ping`, `--quiet` and `sysexits`-style exit codes (64 usage, 65 invalid message, 69 unreachable, 70 rejected).
- Protocol, parsing and the socket client live in `Shared/`, compiled into both targets, so the app and the CLI share one schema and the CLI's logic is unit tested in the app's test bundle.

### Tool-specific adapters live in `notchctl`, not in the app

- `notchctl hook <adapter>` hands the tool's own hook payload to an `AgentHookAdapter` (`Shared/AgentAdapters/`): `claude-code` (Claude Code hooks, JSON on stdin), `codex` (Codex lifecycle hooks, JSON on stdin) and `codex-notify` (Codex's legacy `notify` program, JSON as the last argument). Adapters are pure functions from payload to generic messages. They are compiled into the app only so they can be unit tested; the app never calls them and only ever sees the generic protocol.
- Adapters are lenient: unknown events, notification types and fields produce no message, a field of an unexpected type counts as missing, and only a payload that isn't a JSON object is an error. Behavior that differs between tool versions is isolated in one place per adapter (`ClaudeCodeNotification`: the `notification_type` field, or the message text for Claude Code before 2.0.37).
- `notchctl hook` never disturbs the tool: nothing on stdout, always exit 0, a bounded stdin read, a ~1 s timeout per message, silence when NotchDeck isn't running.
- **Privacy by default:** adapters read only event names, session IDs, working directories, tool names and the tools' own notification text. Prompts, tool input and output, assistant messages and transcripts are never forwarded. `--prompt-as-task` is an explicit opt-in that shows the first line of each prompt as the task.
- Setup is documentation ([Claude Code](../integrations/claude-code.md), [Codex](../integrations/codex.md)): NotchDeck never edits a tool's configuration files.

### Presentation through the Activity Engine

- `DeveloperActivityProvider` is an ordinary `ActivityProvider`. It keeps the sessions in memory (`DeveloperSessionCollection`, at most 12) and publishes one activity per session; the engine decides what the notch shows.
- `DeveloperActivityRules` (pure, unit tested) sets placement, priority and lifetime: busy 25 (above music, below a running timer or an imminent meeting), waiting 30, needs input or permission 50 (peeks), completed 30 for 10 s then listed in the command center for up to an hour, failed 50 for 30 s then listed, cancelled 20 for 5 s. Busy and waiting sessions silent for 30 minutes, and sessions that need attention silent for 8 hours, are removed. The provider wakes only at the next of these boundaries.
- Actions: Open Terminal (only known, running terminals or editors are brought forward; otherwise Terminal opens in the validated workspace), Open Workspace, Dismiss.

## Alternatives Considered

- **XPC / a Mach service.** The most "Apple" transport, but a command-line tool can only look up a Mach service that launchd knows about: it needs a LaunchAgent (or an `SMAppService` agent) registered for the service, which means another installed component and lifecycle to manage for an accessory app. A Unix socket gives the same locality with a kernel-verified peer user ID and no registration.
- **Loopback HTTP with a token.** Easy for any language, but it is a network listener, which `SECURITY.md` forbids without strong reason; reachable by anything that can open a TCP connection, including web pages trying DNS rebinding; and it needs token generation, storage and distribution.
- **Distributed notifications** (`DistributedNotificationCenter`). No listener to manage, but any process can post them, the receiver can't authenticate the sender, payloads are limited and there is no reply to report validation errors.
- **A `notchdeck://` URL scheme.** Any app or web page can open it, it launches NotchDeck when it isn't running, and there is no reply.
- **A watched drop directory.** Tools write files that the app picks up. Racy (partial writes), leaves files behind, causes file-system churn and wake-ups, and has no reply.
- **A shared-secret token on top of the socket.** Adds little: the socket is already limited to the user by file permissions and `getpeereid`, and any same-user process that could misuse the socket could also read the token. May be revisited with the App Sandbox (see Consequences).
- **Adapters inside the app** (the app parses Claude Code and Codex payloads). Ties the app to tool versions and makes it tool-specific; with adapters in `notchctl`, the app's input is always the small generic schema.
- **Terminal scraping or reading agents' transcript files.** Forbidden by the Phase 5 brief, brittle across versions, and it would read far more private content than needed.

## Consequences

- Any tool can integrate with one shell command and no change to NotchDeck. Claude Code and Codex need a one-time hooks setup that the user does by hand (documented, copy-paste).
- Idle cost is nil: no polling, no timers while no session is shown; the listener only wakes on connections.
- The adapters have to track the tools' hook formats. They ignore what they don't know, so a new tool version degrades to less detail rather than errors; their tests use the documented payloads, and each integration doc records the version it was verified against.
- Some states can't be observed through hooks (for example, interrupting Claude Code runs no hook), so stale-session timeouts and Dismiss are part of the design.
- **App Sandbox follow-up** ([ADR 0003](0003-app-runtime-configuration.md)): a sandboxed app can't create a socket in the user's Application Support folder. The socket will move into an app group container that `notchctl` (signed with the same team) can reach, and `DeveloperBridgeLocation` is the single place to change.
- **Code-signing follow-up:** once NotchDeck ships with Developer ID signing, the server can additionally verify the peer's code signature (e.g. `notchctl`'s team ID) on top of the user ID check, and `notchctl` can verify it talks to the real app. Same-user processes are trusted today, as they are for every other per-user resource.
