import SwiftUI

/// The Live Activity: a glyph in the leading ear and an accessory in the trailing ear,
/// with the (physical or virtual) notch between them.
struct CompactActivityView: View {
    let activity: NotchActivity
    let notchSize: CGSize

    var body: some View {
        HStack(spacing: 0) {
            ActivityGlyph(presentation: activity.presentation)
                .frame(width: NotchLayout.compactEarWidth)
            Spacer(minLength: notchSize.width)
            CompactAccessoryView(activity: activity)
                .frame(width: NotchLayout.compactEarWidth - 8)
                .padding(.trailing, 8)
        }
        .frame(height: notchSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(activity.title))
        .accessibilityValue(Text(activity.subtitle ?? ""))
    }
}
