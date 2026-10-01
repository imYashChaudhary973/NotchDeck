import SwiftUI

/// Shown while something is dragged over the notch.
///
/// Phase 1 only detects the drag; storing items arrives with the File Shelf (Phase 4).
struct ShelfDropView: View {
    let notchSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchSize.height)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 20, weight: .medium))
                        Text("Drop Here")
                            .font(.system(size: 13, weight: .semibold))
                        Text("The file shelf isn't available yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .accessibilityElement(children: .combine)
    }
}
