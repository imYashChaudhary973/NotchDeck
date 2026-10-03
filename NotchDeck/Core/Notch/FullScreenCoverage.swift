import AppKit
import CoreGraphics

/// Detects whether a full-screen window covers a display, using only public window-list data.
///
/// Only window layers and bounds are read — never titles or contents — so no
/// Screen Recording permission is needed. The pure rules are separated from
/// `CGWindowListCopyWindowInfo` for testing.
enum FullScreenCoverage {
    /// The parts of a `CGWindowListCopyWindowInfo` entry the rule needs.
    struct Window: Equatable, Sendable {
        /// `kCGWindowLayer`. Ordinary app windows, including native full-screen ones, use layer 0.
        var layer: Int
        /// `kCGWindowBounds`, in CoreGraphics global coordinates (origin top-left of the primary display).
        var bounds: CGRect
        var ownerPID: pid_t
    }

    /// Whether any other app's ordinary window covers the whole screen.
    ///
    /// Zoomed (maximized) windows stop below the menu bar, so they don't count.
    ///
    /// - Parameters:
    ///   - screenFrame: The screen, in CoreGraphics global coordinates.
    ///   - windows: On-screen windows.
    ///   - ownPID: NotchDeck's process, whose windows are ignored.
    static func isCovered(screenFrame: CGRect, windows: [Window], ownPID: pid_t) -> Bool {
        windows.contains { window in
            window.layer == 0
                && window.ownerPID != ownPID
                && window.bounds.contains(screenFrame)
        }
    }

    /// Converts an AppKit global rect (origin bottom-left of the primary display) to
    /// CoreGraphics global coordinates (origin top-left of the primary display).
    static func coreGraphicsRect(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Queries the window server for the given AppKit screen frame.
    @MainActor
    static func isCovered(appKitScreenFrame: CGRect) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let screenFrame = coreGraphicsRect(fromAppKit: appKitScreenFrame, primaryScreenHeight: primary.frame.height)
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let windows = info.compactMap(window(from:))
        return isCovered(screenFrame: screenFrame, windows: windows, ownPID: ProcessInfo.processInfo.processIdentifier)
    }

    private static func window(from entry: [String: Any]) -> Window? {
        guard let layer = entry[kCGWindowLayer as String] as? Int,
              let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
              let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
        else { return nil }
        return Window(layer: layer, bounds: bounds, ownerPID: pid)
    }
}

/// Whether the notch panel should be on screen.
enum NotchVisibility {
    /// A physical notch is always shown: full-screen apps leave the camera housing's band black.
    /// A virtual notch would cover a full-screen app's content, so it hides while resting
    /// and appears only for transient states (e.g. an attention peek).
    static func isVisible(
        state: NotchPresentationState,
        hasPhysicalNotch: Bool,
        isFullScreenCovered: Bool
    ) -> Bool {
        hasPhysicalNotch || !isFullScreenCovered || state.isTransient
    }
}
