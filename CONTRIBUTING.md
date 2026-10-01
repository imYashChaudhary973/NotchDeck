# Contributing

Thanks for helping build NotchDeck. Coding agents should read [`AGENTS.md`](AGENTS.md) first; its rules apply to everyone.

## Branches

- `main` is always buildable.
- Work on a short-lived branch, e.g. `feature/timer-provider`, `fix/notch-geometry`, `docs/adr-activity-engine`, `chore/…`.
- Open a pull request into `main`; keep PRs small and focused on one change.
- Never force-push to `main`.

## Before Submitting

1. **Build** the project (Debug) with no new warnings.
2. **Run tests:** `xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck test`
3. **Add tests** for new state or business logic.
4. **Update documentation** for any architectural change — and add an ADR in `docs/decisions/` for significant decisions.
5. **Update `CHANGELOG.md`** under *Unreleased* for user-visible or architectural changes.

## Guidelines

- **Respect the architecture.** Features publish activities; they never manipulate the notch directly.
- **Avoid unnecessary dependencies.** Prefer Apple frameworks. New dependencies need written justification.
- **Stay native.** SwiftUI and AppKit, system materials and behaviors; no web shells.
- **Respect privacy.** Follow [`PRIVACY.md`](PRIVACY.md); never log sensitive data.
- **Respect performance.** NotchDeck runs all day — prefer events over polling and keep idle cost near zero.
- **Stay in scope.** Implement the current phase only; don't pre-build future phases.

## Commit Messages

Use concise, conventional-style messages, e.g. `feat: add timer activity provider`, `fix: …`, `docs: …`, `chore: …`, `test: …`.
