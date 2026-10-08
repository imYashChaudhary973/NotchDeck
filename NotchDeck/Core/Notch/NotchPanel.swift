import AppKit

/// The borderless, transparent, non-activating panel that hosts the notch surface.
///
/// - Sits above the menu bar so it can extend out of the notch.
/// - Joins every Space and appears over full-screen apps.
/// - Never becomes key or main, so it never steals focus from the user's app.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Note: don't set `isFloatingPanel`; it resets `level` to `.floating`, below the menu bar.
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit normally keeps windows below the menu bar; the notch panel must sit flush with the top edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
