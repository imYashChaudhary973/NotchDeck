import AppKit
import SwiftUI

/// The featured card for `collection` content: a header with the activity's actions as icon buttons,
/// then the items as a strip of tiles (shelf) or as rows (clipboard history).
struct CollectionFeatured: View {
    let activity: NotchActivity
    let collection: CollectionContent
    let model: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                FeaturedHeader(activity: activity)
                ForEach(activity.actions) { action in
                    IconActionButton(action: action) { model.perform(action, on: activity) }
                }
            }

            if collection.items.isEmpty {
                if let emptyText = collection.emptyText {
                    Text(emptyText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                switch collection.layout {
                case .tiles:
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(collection.items) { item in
                                CollectionTile(item: item, activity: activity, model: model)
                            }
                        }
                    }
                    .frame(height: CollectionTile.height)
                case .rows:
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(collection.items) { item in
                            CollectionRow(item: item, activity: activity, model: model)
                        }
                        if collection.hiddenCount > 0 {
                            Text("+\(collection.hiddenCount) more")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 6)
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }
}

/// The trailing side of a `collection` row in the widget column: the first thumbnails (draggable)
/// for tiles, the subtitle for rows.
struct CollectionWidgetTrailing: View {
    let activity: NotchActivity
    let collection: CollectionContent

    private let maxThumbnails = 3

    var body: some View {
        switch collection.layout {
        case .tiles:
            HStack(spacing: 4) {
                ForEach(collection.items.prefix(maxThumbnails)) { item in
                    CollectionThumbnail(item: item, size: 20)
                        .opacity(item.isUnavailable ? 0.5 : 1)
                        .collectionDrag(item)
                        .help(item.title)
                }
                if collection.items.count > maxThumbnails {
                    Text("+\(collection.items.count - maxThumbnails)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        case .rows:
            if let subtitle = activity.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// A shelf item: its thumbnail and name. Click to use it, drag it out, right-click for more.
private struct CollectionTile: View {
    static let height: CGFloat = 72

    let item: CollectionContent.Item
    let activity: NotchActivity
    let model: NotchViewModel

    var body: some View {
        VStack(spacing: 4) {
            CollectionThumbnail(item: item, size: 40)
                .overlay(alignment: .topTrailing) {
                    if item.isPinned { PinBadge().offset(x: 5, y: -4) }
                }
            Text(item.title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 4)
        .frame(width: 68, height: Self.height)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
        .opacity(item.isUnavailable ? 0.5 : 1)
        .collectionInteractions(item, activity: activity, model: model)
    }
}

/// A clipboard entry: icon, thumbnail or swatch, one line of text, pin and age. Click to copy it.
private struct CollectionRow: View {
    let item: CollectionContent.Item
    let activity: NotchActivity
    let model: NotchViewModel

    var body: some View {
        HStack(spacing: 8) {
            CollectionThumbnail(item: item, size: 18)
            Text(item.title)
                .font(item.isMonospaced ? .system(size: 11, design: .monospaced) : .system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .opacity(item.isUnavailable ? 0.5 : 1)
        .collectionInteractions(item, activity: activity, model: model)
    }
}

/// A thumbnail, a color swatch, or the item's symbol on a tile.
struct CollectionThumbnail: View {
    let item: CollectionContent.Item
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        Group {
            if let data = item.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if let color = item.color {
                shape
                    .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                    .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 1))
            } else {
                Image(systemName: item.symbolName)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: size, height: size)
                    .background(shape.fill(.white.opacity(0.1)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct PinBadge: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 13, height: 13)
            .background(Circle().fill(.purple))
            .accessibilityHidden(true)
    }
}

/// An activity action drawn as a small icon button (the title is its tooltip and accessibility label).
private struct IconActionButton: View {
    let action: ActivityAction
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            Image(systemName: action.systemImage ?? "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(action.isDestructive ? .red.opacity(0.9) : .white.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(action.title)
        .accessibilityLabel(action.title)
    }
}

extension CollectionContent.Payload {
    /// What a drag out of the notch carries.
    func itemProvider() -> NSItemProvider {
        switch self {
        case .file(let url): NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
        case .url(let url): NSItemProvider(object: url as NSURL)
        case .text(let text): NSItemProvider(object: text as NSString)
        }
    }
}

private extension View {
    /// Click for the item's primary action, drag it out, right-click for its menu (and Share).
    func collectionInteractions(_ item: CollectionContent.Item, activity: NotchActivity, model: NotchViewModel) -> some View {
        contentShape(Rectangle())
            .onTapGesture {
                if let id = item.primaryActionID { model.perform(actionID: id, on: activity) }
            }
            .collectionDrag(item)
            .contextMenu { CollectionItemMenu(item: item, activity: activity, model: model) }
            .help([item.title, item.subtitle].compactMap { $0 }.joined(separator: "\n"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.title)
            .accessibilityValue(item.subtitle ?? "")
            .accessibilityAddTraits(item.primaryActionID == nil ? [] : .isButton)
            .accessibilityAction {
                if let id = item.primaryActionID { model.perform(actionID: id, on: activity) }
            }
    }
}

extension View {
    /// Lets an available item with a payload be dragged out of the notch.
    @ViewBuilder
    func collectionDrag(_ item: CollectionContent.Item) -> some View {
        if let payload = item.payload, !item.isUnavailable {
            onDrag { payload.itemProvider() }
        } else {
            self
        }
    }
}

private struct CollectionItemMenu: View {
    let item: CollectionContent.Item
    let activity: NotchActivity
    let model: NotchViewModel

    var body: some View {
        let regular = item.menuActions.filter { !$0.isDestructive }
        let destructive = item.menuActions.filter(\.isDestructive)
        ForEach(regular) { action in
            menuButton(action)
        }
        if let payload = item.payload, !item.isUnavailable {
            switch payload {
            case .file(let url), .url(let url): ShareLink(item: url)
            case .text(let text): ShareLink(item: text)
            }
        }
        if !destructive.isEmpty {
            Divider()
            ForEach(destructive) { action in
                menuButton(action)
            }
        }
    }

    private func menuButton(_ action: ActivityAction) -> some View {
        Button(role: action.isDestructive ? .destructive : nil) {
            model.perform(action, on: activity)
        } label: {
            if let systemImage = action.systemImage {
                Label(action.title, systemImage: systemImage)
            } else {
                Text(action.title)
            }
        }
    }
}
