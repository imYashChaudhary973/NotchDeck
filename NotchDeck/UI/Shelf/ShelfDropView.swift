import SwiftUI

/// Shown while something is dragged over the notch: the dragged item and the drop tiles.
/// The tile under the pointer highlights; a drop anywhere else keeps the item on the shelf.
struct ShelfDropView: View {
    let model: NotchViewModel
    let notchSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchSize.height)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(model.shelfDrag?.itemDescription ?? "Drop here")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("Drop to keep it on the shelf")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 10) {
                    ForEach(NotchDrop.Target.allCases, id: \.self) { target in
                        ShelfTileView(target: target, model: model)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
    }
}

extension NotchDrop.Target {
    var title: String {
        switch self {
        case .shelf: "Shelf"
        case .copy: "Copy"
        case .airDrop: "AirDrop"
        }
    }

    var subtitle: String {
        switch self {
        case .shelf: "Keep for later"
        case .copy: "Onto the clipboard"
        case .airDrop: "Send to a device"
        }
    }

    var symbolName: String {
        switch self {
        case .shelf: "tray.and.arrow.down.fill"
        case .copy: "doc.on.doc.fill"
        case .airDrop: "dot.radiowaves.left.and.right"
        }
    }

    var accent: ActivityAccent {
        switch self {
        case .shelf: .purple
        case .copy: .green
        case .airDrop: .blue
        }
    }
}

private struct ShelfTileView: View {
    let target: NotchDrop.Target
    let model: NotchViewModel

    @State private var frame: CGRect = .zero

    var body: some View {
        let isTargeted = model.shelfDrag.map { frame.contains($0.location) } ?? false
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        VStack(spacing: 6) {
            IconTile(
                presentation: ActivityPresentation(symbolName: target.symbolName, accent: target.accent),
                size: 30
            )
            Text(target.title)
                .font(.system(size: 13, weight: .semibold))
            Text(target.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(shape.fill(.white.opacity(isTargeted ? 0.1 : 0.03)))
        .overlay(
            shape.strokeBorder(
                isTargeted ? target.accent.color.opacity(0.8) : .white.opacity(0.22),
                style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [6, 5])
            )
        )
        .scaleEffect(isTargeted ? 1.03 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isTargeted)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newFrame in
            frame = newFrame
            model.setShelfTileFrame(newFrame, for: target)
        }
        .accessibilityElement(children: .combine)
    }
}
