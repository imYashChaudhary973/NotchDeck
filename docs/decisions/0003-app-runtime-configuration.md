# 0003. App Runtime Configuration

- Status: Accepted (sandboxing to be revisited before first distribution)
- Date: 2026-10-02

## Context

Phase 1 needed decisions that were left open in Phase 0: minimum macOS version, activation policy, App Sandbox and Swift concurrency settings.

## Decision

- **Deployment target: macOS 14.0 (Sonoma).** Required for the Observation framework (`@Observable`), `NSApp.activate()` and modern SwiftUI APIs used throughout. Notch geometry APIs need macOS 12, so 14 is the binding constraint.
- **Accessory app** (`LSUIElement = YES`): no Dock icon and no main window. A `MenuBarExtra` provides Settings, the Debug panel (Debug builds) and Quit. Settings and Debug windows are AppKit-managed (`AuxiliaryWindowPresenter`), so nothing opens at launch.
- **App Sandbox: off for now; Hardened Runtime: on.** Phase 1 works either way, but later phases (AppleScript-based media control, local IPC with `notchctl`, file shelf) interact with sandbox entitlements in ways not yet designed. A distribution ADR must revisit this before the first release.
- **Swift 6 language mode** with explicit `@MainActor` on UI and engine types. Pure logic types (`ActivityStore`, `ActivityResolver`, `NotchStateMachine`, `NotchGeometry`) are `Sendable` value types. Default main-actor isolation is not enabled.
- **Launch at Login** uses `SMAppService.mainApp`. Status is read back from the system rather than stored.
- **Debug-only code** (debug provider and panel) is compiled only in Debug (`#if DEBUG`).

## Consequences

- Users on macOS 13 or earlier are not supported.
- No entitlements file exists yet. Adding one is part of the sandbox/distribution decision.
- Launch at Login may report "requires approval" or fail for builds run from DerivedData. It is expected to work for an app installed in `/Applications`.
