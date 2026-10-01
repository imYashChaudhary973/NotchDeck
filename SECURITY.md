# Security

## Reporting a Vulnerability

A dedicated reporting channel has not been set up yet.

**Placeholder:** until one exists, please report vulnerabilities privately via [GitHub private vulnerability reporting](https://github.com/imYashChaudhary973/NotchDeck/security/advisories/new) (if enabled for the repository) or by contacting the maintainer directly. Please do not open public issues for security problems.

## Project Security Rules

### Secrets, tokens and credentials

- Never commit secrets, API keys, access tokens, certificates, provisioning profiles or passwords.
- Never print or log tokens or credentials.
- Credentials needed at runtime are stored in the **Keychain**.
- Personal signing settings (e.g. `DEVELOPMENT_TEAM`) are kept out of shared project files.
- If a secret is committed accidentally, treat it as compromised: rotate it first, then remove it.

### Local IPC

- Developer-agent integrations (Phase 5) **must use secure local IPC**.
- NotchDeck must **never expose an unauthenticated network listener**, on any interface — including `localhost`.
- Prefer transports that are inherently local and permissioned (e.g. XPC, Unix domain sockets with restrictive file permissions) and authenticate peers.
- A local HTTP transport (mentioned as an option in the engineering plan) is only acceptable if it is loopback-only **and** authenticated, and requires an ADR.
- Treat every message from another process as untrusted input.

### Input validation

- Validate and bound all external input: IPC messages, URLs, URL-scheme invocations, dropped files and pasteboard data.
- Only open URLs with expected schemes; never execute or `open` arbitrary strings received from other processes.
- Resolve and validate file paths before use; handle symlinks, missing files and permission errors safely.
- Use structured decoding (e.g. `Codable`) with versioned schemas rather than ad-hoc parsing.

### Least privilege

- Request only the entitlements and permissions a shipped feature actually needs.
- Do not request permissions speculatively for future features.
- Prefer supported, public Apple APIs; no private frameworks for core functionality.

### Dependency review

- The project currently has **no third-party dependencies**; keep it that way unless there is a strong reason.
- Any new dependency requires justification in the PR (why Apple frameworks are insufficient), a review of its maintenance status and license, and a pinned version.
