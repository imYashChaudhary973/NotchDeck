# Claude Code

NotchDeck shows what Claude Code is doing — working, running a command, waiting for your permission, finished — using Claude Code's own [hooks](https://code.claude.com/docs/en/hooks). Claude Code runs `notchctl hook claude-code` at each lifecycle event and passes the event as JSON on standard input; the `claude-code` adapter in `notchctl` turns it into a [developer activity message](../developer-activity-protocol.md). Nothing reads your terminal.

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

3. **Add the hooks** to `~/.claude/settings.json` (all your projects). For a single project use `.claude/settings.json` (shared with the repository) or `.claude/settings.local.json` (just you). If the file already has a `hooks` object, add these events to it.

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

   Claude Code picks up edits to settings files automatically; `/hooks` lists what it loaded. Omitting `matcher` runs a hook for every tool and notification type, which the adapter needs. `SessionEnd` has no `timeout` on purpose: Claude Code gives all `SessionEnd` hooks a shared 1.5-second budget when you exit, and a per-hook `timeout` would raise that budget.

4. **Use Claude Code as usual.** Submit a prompt and the notch shows "Claude · *project*".

If Claude Code runs from an app (the VS Code extension, Claude Desktop) rather than your shell, its `PATH` may not include `/usr/local/bin`. Use the absolute path in `command` instead, e.g. `"/usr/local/bin/notchctl hook claude-code"` or `"/Applications/NotchDeck.app/Contents/MacOS/notchctl hook claude-code"`.

You can leave out events you don't want, but keep `PostToolUse` and `PostToolUseFailure` if you keep `PermissionRequest` or `Notification`: they are what returns the session to "working" after you answer.

## What you see

| Claude Code event | NotchDeck shows |
| --- | --- |
| `UserPromptSubmit` | Working. The task is the session's custom title if you named it (`--name`, `/rename`), or the prompt's first line with [`--prompt-as-task`](#privacy). |
| `PreToolUse` | `Bash`, `PowerShell`: Running command. `AskUserQuestion`: Needs input, "Claude has a question". `ExitPlanMode`: Needs input, "Claude's plan is ready for review". Other tools: Working, with a short description such as "Editing files", "Reading files", "Searching files", "Searching the web", "Running a subagent", "Updating the plan", "Using a skill", "Using github" (an MCP server) or "Using *ToolName*". |
| `PermissionRequest` | Needs permission, "Claude needs your permission to use Bash" (the tool's name, or the MCP server's). |
| `PostToolUse`, `PostToolUseFailure` | Working. |
| `Notification` | `permission_prompt`: Needs permission, with Claude Code's notification text. `elicitation_dialog`, `elicitation_url_dialog`, `quota_auto_resume_stale`: Needs input. `elicitation_complete`, `elicitation_response`, `quota_auto_resume_fired`: Working. Everything else — `idle_prompt`, `auth_success`, `agent_needs_input`, `agent_completed`, `quota_auto_resume_disabled`, types added later — changes nothing. |
| `Elicitation` | Needs input, "*server* needs your input". |
| `ElicitationResult` | Working. |
| `PreCompact` | Automatic compaction: Working, "Compacting conversation". A manual `/compact` changes nothing (no `Stop` follows it). |
| `Stop` | Finished. |
| `StopFailure` | Failed, with a fixed description of the API error type, e.g. "Rate limit reached" or "Authentication failed". The API's own error text isn't shown. |
| `SessionEnd` | The session is removed. |
| `SessionStart`, `SubagentStart`, `SubagentStop`, `PostCompact`, any other event | Nothing. |

Why some events are ignored:

- **`SessionStart`**: a session you just opened and haven't used yet shouldn't take over the notch. It appears with your first prompt.
- **`idle_prompt`**: Claude Code sends it about a minute after a reply; `Stop` already reported that the turn finished, and a "needs you" reminder would keep the notch busy for a session you walked away from.
- **`SubagentStart`, `SubagentStop`**: they also fire for Claude Code's internal agents (prompt suggestions, `/btw`) after a turn. Subagents' tool use still shows through `PreToolUse`.

Each Claude Code session is one NotchDeck session, identified by Claude Code's `session_id`. The workspace is `CLAUDE_PROJECT_DIR` (the project root, which stays put when Claude changes directory), otherwise the event's `cwd`; the project name is the workspace folder's name. **Open Terminal** brings forward the terminal or editor Claude Code runs in, detected from `__CFBundleIdentifier` or `TERM_PROGRAM`.

## Privacy

The notch is visible to anyone who can see your screen, including in screen shares and recordings. The adapter therefore reads only the event name, session ID, working directory, tool names, notification type, MCP server name, compaction trigger, error type, the session's custom title, and Claude Code's own notification text ("Claude needs your permission to use Bash").

Never forwarded: your prompts, tool input (commands, file paths, file contents, URLs, questions, plans), tool output, Claude's replies (`last_assistant_message`), error details, and the transcript. Claude Code's `transcript_path` is never opened.

**Opt-in: `--prompt-as-task`.** To see what each task is about, add the flag to the `UserPromptSubmit` hook only:

```json
"UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "notchctl hook claude-code --prompt-as-task", "timeout": 5 }] }]
```

The task is then the first non-empty line of each prompt, cut to 240 characters. Prompts that start with markup — pasted content (`<pasted_content …>`) and Claude Code's own background-task messages — are skipped. The text stays in NotchDeck's memory while the session is shown; it is never stored, logged or sent anywhere.

See [`PRIVACY.md`](../../PRIVACY.md) for everything NotchDeck does with developer activity.

## Troubleshooting

- **Nothing appears.** Run `notchctl ping`. Exit status 69 ("NotchDeck isn't listening") means NotchDeck isn't running or **Settings ▸ Features ▸ Developer agents** is off. "command not found" means `notchctl` isn't on your `PATH`: use the absolute path in the hook command.
- **Check that Claude Code loaded the hooks** with `/hooks`. Hooks don't run when `disableAllHooks` is set, or when an administrator set `allowManagedHooksOnly`.
- **Simulate an event** without Claude Code:

  ```bash
  echo '{"session_id":"test","cwd":"'"$PWD"'","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}' | notchctl hook claude-code
  echo '{"session_id":"test","hook_event_name":"SessionEnd"}' | notchctl hook claude-code
  ```

  The first shows "Claude needs you"; the second removes the session. `notchctl hook` prints a one-line warning on standard error if it can't read the payload or reach NotchDeck.
- **Hook details** are in Claude Code's debug log: start `claude --debug` and read `~/.claude/debug/<session-id>.txt`. Claude Code writes the hooks' standard error there.
- **The hooks never slow Claude down noticeably or block it.** `notchctl hook` prints nothing on standard output (which Claude Code would add to the conversation for `UserPromptSubmit`), always exits 0 (never "exit 2", which would block), gives up on NotchDeck after about a second, and returns at once when NotchDeck isn't running. The `timeout` of 5 seconds is only a backstop. Hooks run synchronously so that events arrive in order; each costs a few milliseconds.

### Known limitations

- **Interrupting Claude** (Esc), including declining a permission prompt with "tell Claude what to do differently", runs no hook: Claude Code doesn't run `Stop` for user interrupts. The notch keeps the last state until your next prompt. Use **Dismiss** to remove it sooner; otherwise a working session is removed after 30 minutes without updates, and one that needs you after 8 hours.
- **Background subagents** keep reporting tool use after Claude's reply, so the session shows "working" again until they finish and Claude replies (and `Stop` runs) once more.
- `permission_prompt` notifications arrive about six seconds after a permission prompt, and only if you haven't typed since. `PermissionRequest` reports the prompt immediately, which is why both are configured.
- Claude Code on the web and other cloud sessions don't read your local settings and can't reach your Mac. Claude Code running on another machine (over SSH) can't reach NotchDeck either: the socket is local only.

## Version notes

Verified on 2026-10-09 against the [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) and the [Claude Code changelog](https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md), current version 2.1.295.

| Claude Code | What changed for this integration |
| --- | --- |
| 1.0.54 | `UserPromptSubmit`; `cwd` in every hook input |
| 1.0.58 | `CLAUDE_PROJECT_DIR` exported to hooks |
| 1.0.85 | `SessionEnd` |
| 2.0.37 | Notification types (`notification_type`, matcher values) |
| 2.0.45 | `PermissionRequest` |
| 2.1.76 | `Elicitation`, `ElicitationResult` |
| 2.1.78 | `StopFailure` |
| 2.1.234 | `quota_auto_resume_*` notification types |

- On older versions, events that don't exist yet simply never fire. If Claude Code complains about an unknown hook event in your settings, remove that event.
- The version-specific part of the adapter is isolated in `ClaudeCodeNotification` (`Shared/AgentAdapters/ClaudeCodeHookAdapter.swift`). With `notification_type`, the type decides. Before 2.0.37, Claude Code sent only the text: a notification mentioning "permission" counts as a permission prompt, anything else (such as "Claude is waiting for your input") is ignored.
- The `Agent` tool was called `Task` in older versions; both are recognized.
- Events, notification types and fields added after this adapter was written are ignored, never an error. Only a payload that isn't a JSON object is rejected, and even then `notchctl hook` exits 0.
