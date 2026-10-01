# Privacy Principles

This document describes the privacy principles NotchDeck is designed and built around. It is an engineering commitment for contributors, not a legal policy.

## Sensitive Systems

NotchDeck is planned to touch several kinds of sensitive local information:

| System | Examples of sensitive data |
| --- | --- |
| **Calendar** | Meeting titles, attendees, locations, video-call links |
| **Clipboard** | Anything a user copies — including passwords, tokens and personal messages |
| **Files** | Filenames, paths and file contents placed on the shelf |
| **Developer activity** | Project paths, repository names, prompts, tool output from Claude Code / Codex / other tools |
| **System information** | Running applications, CPU / memory usage, audio devices |

All of it is treated as private by default.

## Principles

1. **Local by default.** Data NotchDeck reads stays on the user's Mac. Nothing is sent off-device unless a feature explicitly requires it and the user understands that.
2. **Contextual permissions.** Permissions (e.g. Calendar access) are requested only when the user enables the feature that needs them — never all at once on first launch — with a clear explanation of why.
3. **Clipboard history stays local.** Clipboard history, when enabled, is stored only on the device, is user-clearable, and is never synced or uploaded by default. Clipboard contents are never written to logs.
4. **Developer activity stays local.** Activity from developer tools is received over a local channel and is not forwarded elsewhere.
5. **Credentials in the Keychain.** Any credentials or tokens NotchDeck ever needs are stored through appropriate system mechanisms such as the Keychain — never in plain-text preferences, files or logs.
6. **Minimal retention.** Keep data only as long as the feature needs it, and give users controls to clear it.
7. **No unnecessary telemetry.** NotchDeck does not collect analytics or usage tracking it doesn't need. If diagnostic reporting is ever proposed, it must be opt-in and documented here first.
8. **Careful logging.** Logs must not contain clipboard contents, calendar details, file contents, or sensitive filenames/paths. Use `os.Logger` privacy annotations (`privacy: .private`) for any dynamic value that could be sensitive.

## For Contributors

Any change that reads a new category of user data, adds a permission, stores user data, or communicates off-device must update this document in the same change.
