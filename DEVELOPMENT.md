# Development

This document describes how to build, run and test NotchDeck locally. Items marked **TBD during Phase 1** have not been decided yet — do not assume values for them.

## Requirements

### macOS version

- **Supported deployment target (minimum macOS for users):** TBD during Phase 1.
  The project is currently configured with `MACOSX_DEPLOYMENT_TARGET = 14.0` as a provisional placeholder so it builds; this is not a final decision.
- **Development machine:** any macOS version that runs the required Xcode.

### Xcode version

- **Required Xcode:** TBD during Phase 1.
- Phase 0 was created and verified with **Xcode 27.0** (Swift 6.4, macOS 27.0 SDK).
- The project uses `objectVersion = 77` (file-system-synchronized groups), which requires **Xcode 16 or later** to open.

### Dependencies

None. No package managers, no third-party frameworks.

## Quick Environment Check

```bash
Scripts/bootstrap.sh
```

Reports macOS/Xcode/Swift versions, Git status and remote, and whether the project is listable. It never modifies anything.

## Opening the Project

```bash
open NotchDeck.xcodeproj
```

Select the shared **NotchDeck** scheme and the **My Mac** destination.

New files placed under `NotchDeck/` or `NotchDeckTests/` are automatically included in their targets (file-system-synchronized groups) — you do not need to edit the project file.

## Building

```bash
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck -configuration Debug build
```

## Running

From Xcode: **Product ▸ Run** (⌘R).

From the command line:

```bash
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck -configuration Debug \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/NotchDeck.app
```

(`build/` is git-ignored.)

## Testing

Tests use **Swift Testing** (`import Testing`).

```bash
xcodebuild -project NotchDeck.xcodeproj -scheme NotchDeck test
```

In Xcode: **Product ▸ Test** (⌘U).

## Configurations

### Debug

- No optimization (`-Onone`), `DEBUG` compilation condition, testability enabled.

### Release

- Whole-module optimization, dSYM generation, assertions disabled.

## Signing

- Currently: **automatic signing, "Sign to Run Locally"** (`CODE_SIGN_IDENTITY = "-"`), no development team set. This lets anyone build and run locally without an Apple Developer account.
- **Do not commit a personal `DEVELOPMENT_TEAM`** into the shared project. If you need team signing locally, set it in Xcode and do not stage that change, or use a local, git-ignored `.xcconfig` (to be introduced when needed).
- Distribution signing, notarization and Developer ID: TBD during Phase 1 (or later release work).
- Bundle identifier: `com.imyashchaudhary.NotchDeck` (provisional — confirm before first distribution).

## Entitlements

- None at present. Hardened Runtime is enabled.
- App Sandbox: **TBD during Phase 1** (some planned features may be constrained by sandboxing; the decision will be recorded in an ADR).

## Permissions

None requested yet. Planned features will need some of the following, each requested **contextually** when the user enables the feature:

| Feature | Likely permission / mechanism |
| --- | --- |
| Calendar | EventKit calendar access |
| Login item | ServiceManagement (`SMAppService`) |
| Clipboard | `NSPasteboard` (no TCC prompt, but privacy-sensitive) |
| Developer agents | Local IPC (design TBD in Phase 5) |

Usage-description strings (`NS…UsageDescription`) are added alongside the feature that needs them.

## Troubleshooting

- **"The project is damaged" / cannot open:** you are on an Xcode older than 16. Upgrade Xcode.
- **Signing errors when building:** make sure no `DEVELOPMENT_TEAM` mismatch was introduced; the shared project builds with "Sign to Run Locally".
- **Stale build behavior:** delete DerivedData for the project (`~/Library/Developer/Xcode/DerivedData/NotchDeck-*`, or `build/` if you used `-derivedDataPath build/DerivedData`).
- **`warning: Metadata extraction skipped, no AppIntents.framework dependency found`:** harmless toolchain notice; not caused by project code.
