# Developer Activity Protocol

- Version: **1**
- Status: Implemented (Phase 5)
- Decision record: [ADR 0008](decisions/0008-developer-activity-bridge.md)

Any tool that runs on your Mac — a coding agent, a build script, a test runner — can show what it is doing in the notch. It reports **sessions**: one unit of work with a status, such as "Claude Code working in Rove". NotchDeck shows the most important session on the notch and lists all of them in the command center.

The protocol is generic. Claude Code and Codex use it through small adapters built into `notchctl` ([Claude Code](integrations/claude-code.md), [Codex](integrations/codex.md)); NotchDeck itself knows nothing about either.

```text
Tool (hook, script, CLI)
    ↓  notchctl agent … | notchctl send | notchctl hook <adapter>
Unix domain socket (local only, same user only)
    ↓
DeveloperBridgeServer → DeveloperActivityProvider → Activity Engine → notch
```

Most tools should call [`notchctl`](#notchctl) and never deal with the socket. The wire format below is for tools that want to talk to the socket directly, and for anyone reviewing the bridge.

## Transport

| | |
| --- | --- |
| Socket | Unix domain stream socket at `~/Library/Application Support/NotchDeck/Bridge/bridge.sock` |
| Exchange | One request and one response per connection |
| Request | One JSON object (UTF-8), ended by a newline (`\n`) or by closing the write side. Bytes after the newline are ignored. |
| Request size | At most 16 KiB (16,384 bytes, not counting the newline). Larger requests are answered with an error without being decoded. |
| Time limit | The request must arrive within 2 seconds of connecting, or NotchDeck answers with an error and closes the connection. |
| Response | One JSON object and a newline; then NotchDeck closes the connection. At most 4 KiB. |
| Concurrency | Up to 8 connections at once; further connections are closed immediately. |

`notchctl` connects to `$NOTCHDECK_SOCKET` instead when that variable holds an absolute path (for tests and development). NotchDeck itself never reads it.

### Response

```json
{"ok":true,"version":1}
```

```json
{"ok":false,"version":1,"error":"Missing required field 'status'."}
```

`version` is the protocol version NotchDeck speaks. `error` is a human-readable reason; its wording isn't part of the protocol, so don't parse it. A `ping` gets the same success response and changes nothing.

### Authentication

There are no tokens or passwords. Access is limited by the operating system:

- The socket's directory (`…/NotchDeck/Bridge`) is owned by you and has mode `0700`. NotchDeck creates it if needed; if it exists, it must be a real directory (not a symlink) owned by you, and its mode is reset to `0700`. Otherwise the bridge doesn't start.
- The socket has mode `0600`.
- For every connection, NotchDeck asks the kernel for the peer's user ID (`getpeereid`). A connection from any other user is closed without being read or answered.
- There is no network listener of any kind — not on `localhost`, not on any interface.
- NotchDeck listens only while **Settings ▸ Features ▸ Developer agents** is on (the default). Turning it off closes the socket and removes the socket file.

If a NotchDeck that didn't shut down cleanly left its socket behind, the next start replaces it. A socket that still answers belongs to a running NotchDeck and is left alone, and so is anything at the path that isn't a socket; in both cases the command center shows "Developer bridge unavailable" with **Retry**.

Every request is treated as untrusted input: size-bounded, decoded structurally (`Codable`), validated field by field, and its text sanitized. Message contents are never logged.

## Messages

```json
{
  "version": 1,
  "type": "event",
  "provider": "my-tool",
  "providerName": "My Tool",
  "session": "run-42",
  "project": "Rove",
  "workspace": "/Users/me/Rove",
  "task": "Implement tab management",
  "status": "working",
  "message": "Running the test suite",
  "progress": 0.4,
  "terminal": "com.apple.Terminal"
}
```

| Key | Type | Required | Rules |
| --- | --- | --- | --- |
| `version` | integer | no (default `1`) | `1` up to the version NotchDeck speaks. A newer version is rejected as unsupported. |
| `type` | string | no (default `event`) | `event`, `end` or `ping` (see [Types](#types)). |
| `provider` | string | for `event` and `end` | Integration ID, e.g. `claude-code`. 1–64 characters: lowercase letters, digits, `.`, `_`, `-`, starting with a letter or digit. Surrounding spaces are trimmed and uppercase letters lowercased. |
| `providerName` | string | no | Display name, e.g. `Claude Code`. Text, at most 64 characters. Default: a known integration's name, otherwise the ID title-cased (`my-tool` → "My Tool"). |
| `session` | string | no | The tool's own session ID. 1–128 characters from `A–Z a–z 0–9 . _ : @ + = / -`. |
| `project` | string | no | Project name. Text, at most 64 characters. Default: the workspace folder's name. |
| `workspace` | string | no | Absolute path of the directory the session works in. At most 1,024 bytes, no control characters. `.` and `..` are resolved lexically; the file system isn't touched. |
| `task` | string | no | What the session is working on. Text, at most 240 characters. |
| `status` | string | for `event` | One of the [statuses](#statuses). |
| `message` | string | no | A short status message, e.g. "Approval required". Text, at most 240 characters. |
| `progress` | number | no | Completion from `0` to `1`. |
| `terminal` | string | no | Bundle identifier of the terminal or editor the session runs in, e.g. `com.googlecode.iterm2`. At most 155 characters: letters, digits, `.` and `-`, starting with a letter or digit. |

- **Text** fields are sanitized: control and invisible formatting characters (including bidirectional overrides) become spaces, runs of whitespace collapse to one space, a field left empty is dropped, and longer text is cut to the limit, ending in "…".
- A value of the wrong JSON type, an identifier that breaks its rule, a relative workspace or a progress outside `0…1` rejects the whole message. Fix the sender rather than relying on partial acceptance.
- `null` counts as absent. Unknown keys are ignored.
- `terminal` is only a hint. NotchDeck brings an app forward only if it is a known terminal or editor that is running.
- `workspace` is untrusted too. NotchDeck checks that it is an existing directory before opening it in Finder or Terminal, and never runs anything in it.

### Types

| Type | Effect |
| --- | --- |
| `event` | Creates the session, or updates it. Keys present replace the stored values; keys left out keep them, so a hook that reports only a status keeps the task. The status message belongs to its status: a new status without a `message` clears the old one. When a finished session (completed, failed, cancelled) reports a busy status again, a new task has begun: elapsed time restarts and the previous task, message and progress are cleared. |
| `end` | Removes the session at once, e.g. because the tool exited. `status` and `progress` are ignored. |
| `ping` | Checks that NotchDeck is listening. Needs no other key and changes nothing. |

### Statuses

| Status | Meaning |
| --- | --- |
| `starting` | The session is starting up. |
| `working` | The agent is working (thinking, editing, using tools). |
| `runningCommand` | The agent is running a shell command. |
| `waiting` | The agent is waiting on something other than you, e.g. a build or a rate limit. |
| `needsInput` | The agent can't continue until you answer a question or review something. |
| `needsPermission` | The agent can't continue until you approve an action. |
| `completed` | The task finished. |
| `failed` | The task failed. |
| `cancelled` | The task was cancelled, e.g. interrupted by you. |

Status names are case-sensitive on the wire. (`notchctl agent update --status` also accepts `running-command`, `needs_input` and other spellings.)

### Session identity

A message is about the session identified by, in order:

1. `provider` + `session`,
2. otherwise `provider` + `workspace` (after it is standardized),
3. otherwise `provider` + `project`,
4. otherwise `provider` alone.

Send the same identifying keys in every message of a session. Prefer a real session ID: without one, two sessions of the same tool in the same directory are one session to NotchDeck. NotchDeck keeps at most 12 sessions; beyond that, finished ones leave first, then the least recently updated.

## Compatibility

- Receivers ignore keys they don't know, so adding an optional key is compatible and doesn't change the version.
- Anything an older NotchDeck would reject or misread — a new status or type, a changed meaning — increases `version`. NotchDeck rejects versions newer than its own (`ok: false`); it keeps accepting older ones.
- Senders should send the lowest version that has what they need. Today that is always `1`.
- Statuses, types and limits listed here are fixed for version 1.

## notchctl

`notchctl` ships inside the app at `NotchDeck.app/Contents/MacOS/notchctl`. **Settings ▸ Developer Agents** shows its exact path and an install command with a **Copy** button. Typically:

```bash
ln -sf /Applications/NotchDeck.app/Contents/MacOS/notchctl /usr/local/bin/notchctl
```

(If `/usr/local/bin` doesn't exist or isn't writable, create it with `sudo mkdir -p /usr/local/bin` and prefix the `ln` with `sudo`, or link into any other directory on your `PATH`, such as `~/.local/bin`.)

```text
notchctl agent <event> --provider ID [options]
notchctl send [JSON | -]
notchctl hook <adapter> [arguments…]
notchctl ping
notchctl help | --version
```

### `notchctl agent <event>`

| Event | Status sent |
| --- | --- |
| `start` | `starting` |
| `working` | `working` |
| `command` | `runningCommand` |
| `waiting` | `waiting` |
| `input` | `needsInput` |
| `permission` | `needsPermission` |
| `complete` | `completed` |
| `fail` | `failed` |
| `cancel` | `cancelled` |
| `update` | `--status` (default `working`) |
| `end` | an `end` message (removes the session) |

| Option | Meaning |
| --- | --- |
| `--provider ID` | Integration ID (required; `--app` is an alias). |
| `--name NAME` | Display name. |
| `--session ID` | The tool's session ID. |
| `--project NAME` | Project name (default: the workspace folder's name). |
| `--workspace PATH` | Directory the session works in (default: the current directory; a relative path is resolved against it). |
| `--task TEXT` | What the session is working on. |
| `--message TEXT` | Short status message. |
| `--progress N` | Completion from 0 to 1. |
| `--terminal ID` | Bundle ID of the terminal or editor (default: detected from `__CFBundleIdentifier` or `TERM_PROGRAM`; `""` for none). |
| `--status STATUS` | Status for `update` only. |
| `-q`, `--quiet` | Print no errors. |

Options also take the `--option=value` form, which is needed for a value that starts with `--`.

### `notchctl send`

Sends one raw message, given as an argument, or on standard input when the argument is `-` or missing. `notchctl` validates it first with the same rules NotchDeck applies.

### `notchctl hook <adapter>`

Translates a tool's own hook payload into messages (see [Claude Code](integrations/claude-code.md) and [Codex](integrations/codex.md)). Adapters: `claude-code`, `codex` (Codex lifecycle hooks) and `codex-notify` (Codex's legacy `notify` program). Adapter names ignore case.

A hook never disturbs the tool that runs it: `notchctl hook` prints nothing on standard output, always exits 0, gives up on a message after about a second, and does nothing when NotchDeck isn't running. Problems (an unreadable payload, NotchDeck not answering) are reported in one line on standard error, unless `--quiet` comes before `hook`. Adapters read standard input only when their tool sends the payload there; payloads over 8 MiB are skipped.

### `notchctl ping`

Prints "NotchDeck is listening." and exits 0 when NotchDeck answers.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success (always, for `hook`) |
| 64 | Usage error: unknown command, option or event, or a missing value |
| 65 | Invalid message: it fails validation, or isn't valid JSON |
| 69 | NotchDeck isn't reachable: not running, Developer agents turned off, or no answer in time |
| 70 | NotchDeck rejected the message, or another failure |

Errors go to standard error. Standard output carries only the output of `help`, `--version` and `ping`.

## Examples

A build script:

```bash
notchctl agent start    --provider build --name "Build" --task "Release build"
notchctl agent update   --provider build --status waiting --message "Waiting for the signing service"
notchctl agent update   --provider build --progress 0.6
notchctl agent complete --provider build --message "Built in 4m 12s"
```

Each of these runs in the same directory, so the default workspace identifies the session. A tool that runs several sessions at once should pass `--session`.

An agent that needs approval:

```bash
notchctl agent permission --provider my-agent --session "$SESSION_ID" --message "Approve deleting 3 files"
notchctl agent working    --provider my-agent --session "$SESSION_ID"
```

Raw JSON:

```bash
notchctl send '{"version":1,"provider":"my-tool","status":"needsInput","workspace":"/Users/me/Rove","message":"Approval required"}'
echo '{"type":"end","provider":"my-tool","workspace":"/Users/me/Rove"}' | notchctl send
```

Talking to the socket directly (any language works the same way: connect, write one line, read one line):

```bash
printf '%s\n' '{"version":1,"type":"ping"}' | nc -U "$HOME/Library/Application Support/NotchDeck/Bridge/bridge.sock"
# {"ok":true,"version":1}
```

## How NotchDeck presents sessions

Each session is one activity in NotchDeck's [Activity Engine](../ARCHITECTURE.md); the engine decides what the notch shows, as for every other feature.

| Status | Where | Priority | For how long |
| --- | --- | --- | --- |
| `starting`, `working`, `runningCommand` | Notch | 25 | Until the next message; removed after 30 minutes without one |
| `waiting` | Notch | 30 | Until the next message; removed after 30 minutes without one |
| `needsInput`, `needsPermission` | Notch, peeks | 50 | Until the next message; removed after 8 hours without one |
| `completed` | Notch, then the command center | 30, then 15 | 10 s on the notch, then listed until dismissed, at most 1 hour |
| `failed` | Notch (peeks), then the command center | 50, then 18 | 30 s on the notch, then listed until dismissed, at most 1 hour |
| `cancelled` | Notch | 20 | 5 s |

- A busy agent (25) sits above playing music (20) and below a running timer or a meeting starting within 15 minutes (30), so an ordinary working agent never hides an imminent meeting. An agent that needs you (50) peeks out of the notch.
- Several sessions coexist: the notch shows the most important one, and the command center lists all of them with provider, project, task, status and elapsed time.
- The notch reads "Claude · Rove" while busy, "Claude needs you" when it needs you, "Rove finished" when done.
- Actions: **Open Terminal** (brings the reported terminal or editor forward if it is a known, running app; otherwise opens Terminal in the workspace), **Open Workspace** (in Finder) and **Dismiss**.
- Sessions live in memory only. Quitting NotchDeck or turning Developer agents off forgets them.

## Integrating a new tool

1. Pick a provider ID (`my-tool`) and, optionally, a display name.
2. Call `notchctl agent …` at the points your tool already knows about: a task starts, it runs a command, it needs the user, it finishes or fails. Pass `--session` if the tool can run more than one session at a time.
3. Send `end` when the session is over, so it disappears at once instead of timing out.
4. Never put secrets in `task` or `message`: the notch is visible to anyone looking at the screen or watching a screen share.

No change to NotchDeck is needed. A tool with its own hook payload format can also get an adapter in `notchctl` (`Shared/AgentAdapters/`, see `AgentHookAdapter`), which keeps tool-specific parsing out of the app.
