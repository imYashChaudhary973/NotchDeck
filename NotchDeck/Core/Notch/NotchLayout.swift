import CoreGraphics

/// The visual metrics of the notch surface for one presentation state.
struct NotchMetrics: Equatable, Sendable {
    /// Size of the notch body (excluding the top flares).
    var bodySize: CGSize
    /// Radius of the concave flares that blend the surface into the top edge of the screen.
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    /// Total size including the flares on both sides.
    var outerSize: CGSize {
        CGSize(width: bodySize.width + topCornerRadius * 2, height: bodySize.height)
    }
}

/// Maps presentation states to surface sizes for a given notch.
enum NotchLayout {
    /// Width of each side "ear" beside the notch in the compact Live Activity.
    static let compactEarWidth: CGFloat = 52
    /// Inset of the compact glyph and accessory from the outer edges of the ears.
    static let compactContentInset: CGFloat = 12
    /// Minimum gap between compact content and the notch.
    static let compactNotchGap: CGFloat = 4
    static let compactGlyphSize: CGFloat = 16
    static let compactAccessoryFontSize: CGFloat = 13

    /// The widest the compact accessory may draw before it scales down.
    static var compactAccessoryMaxWidth: CGFloat {
        compactEarWidth - compactContentInset - compactNotchGap
    }
    static let peekWidth: CGFloat = 420
    static let peekContentHeight: CGFloat = 56
    static let expandedWidth: CGFloat = 600
    /// Used for the expanded height until the content has been measured.
    static let defaultExpandedContentHeight: CGFloat = 120
    /// The expanded surface fits its content within these bounds.
    static let expandedContentHeightRange: ClosedRange<CGFloat> = 56...300
    static let shelfContentHeight: CGFloat = 156

    /// - Parameter expandedContentHeight: Measured height of the expanded content below the notch row.
    static func metrics(
        for state: NotchPresentationState,
        notchSize: CGSize,
        expandedContentHeight: CGFloat? = nil
    ) -> NotchMetrics {
        let notchWidth = notchSize.width
        let notchHeight = notchSize.height

        switch state {
        case .idle:
            return NotchMetrics(
                bodySize: notchSize,
                // No flares at rest: nothing should be visible outside the physical notch.
                topCornerRadius: 0,
                bottomCornerRadius: min(notchHeight / 3, 10)
            )
        case .liveActivity:
            return NotchMetrics(
                bodySize: CGSize(width: notchWidth + compactEarWidth * 2, height: notchHeight),
                topCornerRadius: 6,
                bottomCornerRadius: min(notchHeight / 3, 12)
            )
        case .peek:
            return NotchMetrics(
                bodySize: CGSize(
                    width: max(peekWidth, notchWidth + compactEarWidth * 2),
                    height: notchHeight + peekContentHeight
                ),
                topCornerRadius: 10,
                bottomCornerRadius: 20
            )
        case .expanded:
            return NotchMetrics(
                bodySize: CGSize(
                    width: max(expandedWidth, notchWidth + 200),
                    height: notchHeight + clampedExpandedContentHeight(expandedContentHeight)
                ),
                topCornerRadius: 14,
                bottomCornerRadius: 28
            )
        case .shelf:
            return NotchMetrics(
                bodySize: CGSize(
                    width: max(expandedWidth, notchWidth + 200),
                    height: notchHeight + shelfContentHeight
                ),
                topCornerRadius: 14,
                bottomCornerRadius: 28
            )
        }
    }

    /// Room for content beside the notch in Peek's top row (inside its 16 pt padding, clear of the notch).
    static func peekSideContentWidth(notchWidth: CGFloat) -> CGFloat {
        let bodyWidth = max(peekWidth, notchWidth + compactEarWidth * 2)
        return max((bodyWidth - notchWidth) / 2 - 16 - compactNotchGap, 0)
    }

    static func clampedExpandedContentHeight(_ measured: CGFloat?) -> CGFloat {
        let range = expandedContentHeightRange
        return min(max((measured ?? defaultExpandedContentHeight).rounded(.up), range.lowerBound), range.upperBound)
    }
}
