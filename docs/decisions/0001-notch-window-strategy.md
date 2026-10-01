# 0001. Notch Window Strategy

- Status: Accepted
- Date: 2026-10-02

## Context

NotchDeck draws a surface that appears to grow out of the MacBook notch. It must:

- sit above the menu bar, flush with the top edge of the screen,
- appear on every Space and over full-screen apps,
- never steal focus from the user's app,
- receive hover, click and drag events, but let clicks elsewhere pass through,
- behave consistently on external displays and Macs without a notch,
- cost nothing while idle.

Only public APIs may be used.

## Decision

**One borderless, transparent, non-activating `NSPanel`** (`NotchPanel`) hosts the whole surface.

- `styleMask: [.borderless, .nonactivatingPanel]`, `isOpaque = false`, clear background, no shadow.
- `level = .mainMenu + 3` so it draws over the menu bar. `isFloatingPanel` is **not** set, because it resets `level` to `.floating`.
- `constrainFrameRect(_:to:)` is overridden to return the frame unchanged; otherwise AppKit pushes the window below the menu bar.
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.
- `canBecomeKey` / `canBecomeMain` return `false`; the hosting view accepts first mouse so buttons work without activating the app.

**Geometry** comes from `NSScreen.safeAreaInsets.top` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (macOS 12+). The notch is the gap between the two auxiliary areas. Displays without a notch get a *virtual notch* (180 pt wide, menu-bar height) centered at the top. `NotchGeometry` is pure and unit tested.

**Display selection**: `Automatic` uses the built-in notched display when connected, otherwise the primary display; `Primary display` always uses the primary. Re-evaluated on `NSApplication.didChangeScreenParametersNotification`.

**Sizing and animation**: the SwiftUI surface animates its size with interruptible springs inside the panel. The panel frame follows the state:
- when growing, the panel is enlarged immediately (to the union of old and new sizes) so the surface can animate outward;
- when shrinking, the panel is resized down only after the collapse animation (≈550 ms), cancelled if another transition arrives.
Transparent panel regions pass clicks through to the windows below.

**Input**:
- Hover: one `NSTrackingArea` (`.activeAlways`) sized to the visible surface, rebuilt when the state changes. Because replaced tracking areas don't report enter/exit under a stationary pointer, the pointer location is reconciled against `NSEvent.mouseLocation` after every change.
- Outside clicks: global + local `NSEvent` monitors for mouse-down, **installed only while a transient state (Peek, Expanded, Shelf) is open**. The idle notch observes no global events.
- Drag: the hosting view registers for file, URL, string and image types; entering it opens the Shelf state. Phase 1 refuses drops (Phase 4 adds the File Shelf).

## Alternatives Considered

- **A fixed, large always-present window.** Simpler animation, but hover detection would need a global mouse-moved monitor (constant wakeups) and the window would cover more of the menu bar.
- **Resizing the window with AppKit animations.** Janky alongside SwiftUI springs and not interruptible.
- **Private CGS/SkyLight window APIs** for levels or Spaces behavior. Rejected by the Private API Rule.
- **Global mouse-moved monitoring for hover.** Wakes the app on every mouse move anywhere; violates the Performance Rule.

## Consequences

- The notch panel needs no permissions (no Accessibility, no Input Monitoring).
- Idle cost was measured at 0% CPU and 0 wakeups.
- Hover can only begin over the visible surface (the physical notch when idle). A wider "approach" region for drag-and-drop is deferred to Phase 4.
- Keyboard input (e.g. Escape to collapse) isn't possible while the panel refuses key status; keyboard navigation will be designed in Phase 6.
