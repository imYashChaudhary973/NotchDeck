# Codex

NotchDeck shows what OpenAI's Codex is doing — working, running a command, waiting for your approval, finished — using Codex's own [lifecycle hooks](https://learn.chatgpt.com/docs/hooks). Codex runs `notchctl hook codex` at each event and passes the event as JSON on standard input; the `codex` adapter in `notchctl` turns it into a [developer activity message](../developer-activity-protocol.md). Nothing reads your terminal.

Codex older than 0.124, which has no hooks turned on by default, can use the [legacy `notify` program](#legacy-notify) instead; it reports only finished turns.

## Setup

1. **Install `notchctl`.** It ships inside the app. **Settings ▸ Developer Agents** shows its path and an install command you can copy, typically:

   ```bash
   ln -sf /Applications/NotchDeck.app/Contents/MacOS/notchctl /usr/local/bin/notchctl
   ```

   If `/usr/local/bin` doesn't exist or isn't writable, run `sudo mkdir -p /usr/local/bin` and prefix the `ln` with `sudo`, or link into another directory on your `PATH`.

2. **Check the connection** while NotchDeck is running:

   ```bash
   notchctl ping
   # NotchDeck is listening.
   ```

3. **Add the hooks** to `~/.codex/hooks.json` (all your projects; `<repo>/.codex/hooks.json` for one trusted project). If the file already has a `hooks` object, add these events to it.

   ```json
   {
     "hooks": {
       "UserPromptSubmit":  [{ "hooks": [{ "type": "command", "command": "notchctl hook codex", "timeout": 5 }] }],
       "PreToolUse":        [{ "hooks": [{ "type": "command", "command": "notchctl hook codex", "timeout": 5 }] }],
       "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "notchctl hook codex", "timeout": 5 }] }],
       "PostToolUse":       [{ "hooks": [{ "type": "command", "command": "notchctl hook codex", "timeout": 5 }] }],
       "PreCompact":        [{ "hooks": [{ "type": "command", "command": "notchctl hook codex", "timeout": 5 }] }],
       "Stop":              [{ "hooks": [{ "type": "command", "command": "notchctl hook codex", "timeout": 5 }] }],
       "Interrupt":         [{ "hooks": [{ "type": "command", "command": "notchctl hook codex", "timeout": 3 }] }],
       "SessionEnd":        [{ "hooks": [{ "type": "command", "command": "notchctl hook codex", "timeout": 3 }] }]
     }
   }
   ```

   The same hooks can be written as inline `[hooks]` tables in `~/.codex/config.toml` (see [Codex's hooks reference](https://learn.chatgpt.com/docs/hooks#config-shape)); use one form, not both. Omitting `matcher` runs a hook for every tool, which the adapter needs. `Interrupt` and `SessionEnd` allow at most 3 seconds.

4. **Trust the hooks.** Codex skips new or changed hooks until you review them: start Codex, open `/hooks` and trust the NotchDeck entries. (Codex prints a warning at startup while hooks wait for review.)

5. **Use Codex as usual.** Submit a prompt and the notch shows "Codex · *project*".

If Codex runs from an app (an editor extension, the desktop app) rather than your shell, its `PATH` may not include `/usr/local/bin`. Use the absolute path in `command`, e.g. `"/usr/local/bin/notchctl hook codex"` or `"/Applications/NotchDeck.app/Contents/MacOS/notchctl hook codex"`.

You can leave out events you don't want, but keep `PostToolUse` if you keep `PermissionRequest`: it is what returns the session to "working" after you approve.

## What you see

| Codex event | NotchDeck shows |
| --- | --- |
| `UserPromptSubmit` | Working. With [`--prompt-as-task`](#privacy), the task is the prompt's first line. |
| `PreToolUse` | `Bash` (shell commands and `exec_command`): Running command. `apply_patch`: Working, "Editing files". `update_plan`: "Updating the plan". `spawn_agent`: "Running a subagent". `view_image`: "Reading files". MCP tools: "Using *server*". Others: "Using *tool_name*". |
| `PermissionRequest` | Needs permission: "Codex needs your approval to run a command" (`Bash`), "… to edit files" (`apply_patch`), "… to use *server*" (MCP), otherwise "Codex needs your approval". |
| `PostToolUse` | Working. |
| `PreCompact` | Automatic compaction: Working, "Compacting conversation". A manual compaction changes nothing. |
| `Stop` | Finished. |
| `Interrupt` | Cancelled (you interrupted the turn). |
| `SessionEnd` | The session is removed. Codex sends it when it closes normally, when you archive or delete an open conversation, and after a conversation has been idle and closed in every client for 30 minutes. |
| `SessionStart`, `SubagentStart`, `SubagentStop`, `PostCompact`, any other event | Nothing. A session appears with your first prompt. |

Hosted tools such as web search don't run hooks, so they show as plain "working".

Each Codex session is one NotchDeck session, identified by Codex's `session_id` (subagents report their parent's). The workspace is the event's `cwd`, and the project name is its folder's name. **Open Terminal** brings forward the terminal or editor Codex runs in, detected from `__CFBundleIdentifier` or `TERM_PROGRAM`.

## Privacy

The notch is visible to anyone who can see your screen, including in screen shares and recordings. The adapter therefore reads only the event name, session ID, working directory, tool names and the compaction trigger.

Never forwarded: your prompts, tool input (commands, patches, file paths, MCP arguments), the approval reason (`tool_input.description`, which can quote the command), tool output, Codex's replies (`last_assistant_message`) and the transcript. `transcript_path` is never opened.

**Opt-in: `--prompt-as-task`.** To see what each task is about, add the flag to the `UserPromptSubmit` hook only:

```json
"UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "notchctl hook codex --prompt-as-task", "timeout": 5 }] }]
```

The task is then the first non-empty line of each prompt, cut to 240 characters; prompts that start with markup (`<…>`) are skipped. The text stays in NotchDeck's memory while the session is shown; it is never stored, logged or sent anywhere.

See [`PRIVACY.md`](../../PRIVACY.md) for everything NotchDeck does with developer activity.

## Legacy notify

Before hooks, Codex could run one external program after each turn. In `~/.codex/config.toml`, as a top-level key (above the first `[table]`):

```toml
notify = ["notchctl", "hook", "codex-notify"]
```

Codex appends a JSON payload as the last argument. Its only documented type, `agent-turn-complete`, shows "Finished" for the session (`thread-id`) and its workspace (`cwd`). There is no "working", "needs permission" or session end with `notify`; a finished session stays in the command center for up to an hour. `last-assistant-message` is never forwarded; with `notify = ["notchctl", "hook", "codex-notify", "--prompt-as-task"]` the first line of the turn's first input message becomes the task.

Use `codex-notify` here, not `codex`: older Codex versions start the notify program with your terminal as its standard input, and the `codex-notify` adapter never reads it. With hooks set up, `notify` adds nothing; use one or the other.

## Troubleshooting

- **Nothing appears.** Run `notchctl ping`. Exit status 69 ("NotchDeck isn't listening") means NotchDeck isn't running or **Settings ▸ Features ▸ Developer agents** is off. "command not found" means `notchctl` isn't on your `PATH`: use the absolute path in the hook command.
- **Check that Codex runs the hooks** in `/hooks`: they must be trusted, and hooks must not be turned off (`[features] hooks = false` in `config.toml` or an administrator's `requirements.toml`).
- **Simulate an event** without Codex:

  ```bash
  echo '{"session_id":"test","cwd":"'"$PWD"'","hook_event_name":"PermissionRequest","tool_name":"Bash"}' | notchctl hook codex
  echo '{"session_id":"test","hook_event_name":"SessionEnd"}' | notchctl hook codex
  ```

  The first shows "Codex needs you"; the second removes the session. `notchctl hook` prints a one-line warning on standard error if it can't read the payload or reach NotchDeck.
- **The hooks never block Codex.** `notchctl hook` prints nothing on standard output (which Codex would add to the conversation for some events), always exits 0, gives up on NotchDeck after about a second, and returns at once when NotchDeck isn't running. Hooks run synchronously so that events arrive in order; each costs a few milliseconds.

### Known limitations

- After you approve a request, the session shows "needs permission" until the approved tool finishes and `PostToolUse` runs; Codex has no event for the decision itself.
- Codex running in the cloud, or on another machine over SSH, can't reach NotchDeck: the socket is local only.

## Version notes

Verified on 2026-10-09 against the [Codex hooks reference](https://learn.chatgpt.com/docs/hooks), the configuration docs ([advanced](https://learn.chatgpt.com/docs/config-file/config-advanced), [reference](https://learn.chatgpt.com/docs/config-file/config-reference)) and the source of Codex 0.162.0 ([openai/codex](https://github.com/openai/codex) at tag `rust-v0.162.0`: the hook input schemas in `codex-rs/hooks/schema/generated/` and `codex-rs/hooks/src/legacy_notify.rs`).

| Codex | What changed for this integration |
| --- | --- |
| before 0.124 | Hooks under development and off by default (feature `codex_hooks`): use [`notify`](#legacy-notify) |
| 0.124 | Hooks stable and on by default (feature `hooks`; `codex_hooks` is a deprecated alias) |
| 0.145 | `SessionEnd` |
| 0.150 | `Interrupt` |

- On older versions, leave out events Codex doesn't know yet (`SessionEnd` before 0.145, `Interrupt` before 0.150) if it warns about them. Without `SessionEnd`, a session ends by timing out: a finished session leaves the command center after an hour.
- `notify` is still supported. Codex documents `agent-turn-complete` as its only type. (`approval-requested` exists only for Codex's built-in TUI notifications, not for `notify`; use the `PermissionRequest` hook instead.) Codex 0.100 and later start the notify program with no standard input and discard its output; earlier versions (checked: 0.20) let it inherit the terminal.
- Events, tools and fields added after this adapter was written are ignored, never an error. Only a payload that isn't a JSON object is rejected, and even then `notchctl hook` exits 0.
