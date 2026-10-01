# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project intends to adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once releases begin.

## [Unreleased]

### Added

- Six-phase engineering plan (`docs/development/engineering-plan.md`), linked from `ROADMAP.md`, `ARCHITECTURE.md` and `AGENTS.md`.
- Phase 0 repository bootstrap:
  - Minimal SwiftUI macOS app target (`NotchDeck`) with a placeholder window, and a Swift Testing unit test target (`NotchDeckTests`) with a smoke test.
  - Shared `NotchDeck` Xcode scheme.
  - Project documentation: `README.md`, `AGENTS.md`, `PRODUCT.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `DEVELOPMENT.md`, `CONTRIBUTING.md`, `PRIVACY.md`, `SECURITY.md`.
  - `docs/` structure for decisions (ADRs), architecture and development notes.
  - `Scripts/bootstrap.sh` for non-destructive environment diagnostics.
  - GitHub issue templates and pull request template.
  - `.gitignore` and `.editorconfig`.
