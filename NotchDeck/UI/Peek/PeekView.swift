import SwiftUI

/// A brief look at the primary activity: the compact row plus title and subtitle.
struct PeekView: View {
    let activity: NotchActivity?
    let notchSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let activity {
                    ActivityGlyph(presentation: activity.presentation)
                }
                Spacer(minLength: notchSize.width)
                if let activity {
                    CompactAccessoryView(activity: activity)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: notchSize.height)

            VStack(spacing: 2) {
                if let activity {
                    Text(activity.title)
                        .font(.system(size: 13, weight: .semibold))
                    if let subtitle = activity.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                        .font(.system(size: 13, weight: .semibold))
                    Text("Nothing happening")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        }
    }
}
