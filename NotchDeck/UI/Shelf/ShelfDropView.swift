import SwiftUI

/// Shown while something is dragged over the notch: the dragged item and three drop tiles.
/// The tile under the pointer highlights.
///
/// Phase 1 only previews the shelf; drops are refused until the File Shelf (Phase 4)
/// implements what each tile does.
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
                    Text("Preview · drops not enabled yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 10) {
                    ForEach(ShelfTile.allCases) { tile in
                        ShelfTileView(tile: tile, dragLocation: model.shelfDrag?.location)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
    }
}

/// Drop targets offered by the shelf. Their behavior is implemented in Phase 4.
enum ShelfTile: String, CaseIterable, Identifiable {
    case tray
    case copy
    case airDrop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tray: "Tray"
        case .copy: "Copy"
        case .airDrop: "AirDrop"
        }
    }

    var subtitle: String {
        switch self {
        case .tray: "Keep for later"
        case .copy: "Onto the clipboard"
        case .airDrop: "Send to a device"
        }
    }

    var symbolName: String {
        switch self {
        case .tray: "tray.and.arrow.down.fill"
        case .copy: "doc.on.doc.fill"
        case .airDrop: "dot.radiowaves.left.and.right"
        }
    }

    var accent: ActivityAccent {
        switch self {
        case .tray: .purple
        case .copy: .green
        case .airDrop: .blue
        }
    }
}

private struct ShelfTileView: View {
    let tile: ShelfTile
    let dragLocation: CGPoint?

    @State private var frame: CGRect = .zero

    var body: some View {
        let isTargeted = dragLocation.map { frame.contains($0) } ?? false
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        VStack(spacing: 6) {
            IconTile(
                presentation: ActivityPresentation(symbolName: tile.symbolName, accent: tile.accent),
                size: 30
            )
            Text(tile.title)
                .font(.system(size: 13, weight: .semibold))
            Text(tile.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(shape.fill(.white.opacity(isTargeted ? 0.1 : 0.03)))
        .overlay(
            shape.strokeBorder(
                isTargeted ? tile.accent.color.opacity(0.8) : .white.opacity(0.22),
                style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [6, 5])
            )
        )
        .scaleEffect(isTargeted ? 1.03 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isTargeted)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newFrame in
            frame = newFrame
        }
        .accessibilityElement(children: .combine)
    }
}
