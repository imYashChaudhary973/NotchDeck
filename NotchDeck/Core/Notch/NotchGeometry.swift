import CoreGraphics

/// Where the notch is on a given screen, in global screen coordinates (AppKit, origin bottom-left).
///
/// On displays without a camera housing, a *virtual notch* centered at the top edge is used,
/// so every display behaves consistently.
struct NotchGeometry: Equatable, Sendable {
    /// Size used for the virtual notch on displays without a physical one.
    static let virtualNotchWidth: CGFloat = 180
    static let minimumVirtualNotchHeight: CGFloat = 24

    /// The full frame of the screen the notch belongs to.
    var screenFrame: CGRect
    /// The notch (physical or virtual), flush with the top of `screenFrame`.
    var notchFrame: CGRect
    var hasPhysicalNotch: Bool

    var notchSize: CGSize { notchFrame.size }

    /// Computes geometry from the values `NSScreen` exposes.
    ///
    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame`.
    ///   - safeAreaTopInset: `NSScreen.safeAreaInsets.top` (non-zero only on notched displays).
    ///   - auxiliaryTopLeftArea: `NSScreen.auxiliaryTopLeftArea` — unobscured area left of the notch.
    ///   - auxiliaryTopRightArea: `NSScreen.auxiliaryTopRightArea` — unobscured area right of the notch.
    ///   - menuBarHeight: Height used for the virtual notch when there is no physical one.
    static func make(
        screenFrame: CGRect,
        safeAreaTopInset: CGFloat,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?,
        menuBarHeight: CGFloat
    ) -> NotchGeometry {
        if safeAreaTopInset > 0,
           let left = auxiliaryTopLeftArea,
           let right = auxiliaryTopRightArea {
            let notchWidth = screenFrame.width - left.width - right.width
            if notchWidth > 0 {
                let frame = CGRect(
                    x: screenFrame.minX + left.width,
                    y: screenFrame.maxY - safeAreaTopInset,
                    width: notchWidth,
                    height: safeAreaTopInset
                )
                return NotchGeometry(screenFrame: screenFrame, notchFrame: frame, hasPhysicalNotch: true)
            }
        }

        let height = max(menuBarHeight, minimumVirtualNotchHeight)
        let width = min(virtualNotchWidth, screenFrame.width)
        let frame = CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
        return NotchGeometry(screenFrame: screenFrame, notchFrame: frame, hasPhysicalNotch: false)
    }

    /// A rect of the given size, horizontally centered on the notch and flush with the top of the screen.
    func topCenteredFrame(size: CGSize) -> CGRect {
        CGRect(
            x: (notchFrame.midX - size.width / 2).rounded(),
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

/// Which display hosts the notch.
enum DisplayPreference: String, Sendable, CaseIterable, Identifiable {
    /// The built-in notched display if one is connected, otherwise the primary display.
    case automatic
    /// Always the primary display (the one with the menu bar in System Settings ▸ Displays).
    case primary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .primary: "Primary display"
        }
    }

    var explanation: String {
        switch self {
        case .automatic: "Uses the built-in notched display when available, otherwise the primary display."
        case .primary: "Always uses the primary display."
        }
    }
}

/// Pure screen-selection rule, separated from `NSScreen` for testing.
enum NotchScreenSelector {
    struct Candidate: Equatable, Sendable {
        var hasPhysicalNotch: Bool
    }

    /// Returns the index of the screen that should host the notch.
    /// `candidates` must be ordered like `NSScreen.screens` (primary first).
    static func select(from candidates: [Candidate], preference: DisplayPreference) -> Int? {
        guard !candidates.isEmpty else { return nil }
        switch preference {
        case .automatic:
            return candidates.firstIndex(where: \.hasPhysicalNotch) ?? 0
        case .primary:
            return 0
        }
    }
}
