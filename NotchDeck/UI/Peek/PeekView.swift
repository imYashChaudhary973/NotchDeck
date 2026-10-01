import SwiftUI

/// A brief look at the primary activity.
///
/// The row beside the notch shows the activity's icon tile and its status accessory.
/// Below it: a segmented level bar for level activities (volume HUD), otherwise title and subtitle.
struct PeekView: View {
    let activity: NotchActivity?
    let notchSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if let activity {
                    if case .level = activity.presentation.content {
                        // HUD style: a bare glyph, like the system volume overlay.
                        Image(systemName: activity.presentation.symbolName)
                            .font(.system(size: 15, weight: .semibold))
                            .accessibilityHidden(true)
                    } else {
                        IconTile(presentation: activity.presentation, size: 24, filled: true)
                    }
                }
                Spacer(minLength: notchSize.width)
                if let activity {
                    trailing(for: activity)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: notchSize.height)

            Group {
                if let activity, case .level(let level) = activity.presentation.content {
                    SegmentedLevelBar(value: level.value, tint: activity.presentation.accent.color)
                        .padding(.horizontal, 22)
                } else {
                    VStack(spacing: 2) {
                        Text(activity?.title ?? Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.system(size: 13, weight: .semibold))
                        Text(activity?.subtitle ?? (activity == nil ? "Nothing happening" : ""))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func trailing(for activity: NotchActivity) -> some View {
        if let status = activity.presentation.statusText {
            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activity.presentation.accent == .neutral ? .white : activity.presentation.accent.color)
                .lineLimit(1)
        } else if case .level(let level) = activity.presentation.content, let text = level.valueText {
            Text(text)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
        } else {
            CompactAccessoryView(activity: activity, fontSize: 12)
        }
    }
}
