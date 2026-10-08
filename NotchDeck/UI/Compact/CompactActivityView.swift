import SwiftUI

/// The Live Activity: a glyph in the leading ear and an accessory in the trailing ear,
/// with the (physical or virtual) notch between them.
///
/// Both are pinned to the outer edges as overlays, so they ride the edges while the ears
/// grow out of the notch instead of being laid out (and shifted) mid-animation.
struct CompactActivityView: View {
    let activity: NotchActivity
    let notchSize: CGSize

    var body: some View {
        Color.clear
            .overlay(alignment: .leading) {
                if case .media(let media) = activity.presentation.content, media.artwork != nil {
                    MediaArtwork(media: media, accent: activity.presentation.accent, cornerRadius: 5)
                        .frame(width: NotchLayout.compactArtworkSize, height: NotchLayout.compactArtworkSize)
                } else {
                    ActivityGlyph(presentation: activity.presentation, size: NotchLayout.compactGlyphSize)
                }
            }
            .overlay(alignment: .trailing) {
                CompactAccessoryView(activity: activity, fontSize: NotchLayout.compactAccessoryFontSize)
                    .frame(maxWidth: NotchLayout.compactAccessoryMaxWidth, alignment: .trailing)
            }
            .padding(.horizontal, NotchLayout.compactContentInset)
            .frame(height: notchSize.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(activity.title))
            .accessibilityValue(Text(activity.subtitle ?? ""))
    }
}
