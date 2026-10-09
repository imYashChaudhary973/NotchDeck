import AppKit
import UniformTypeIdentifiers

/// Content dropped on the notch's shelf, and the drop target it landed on.
///
/// The notch reads the items from the drag pasteboard while it is still valid (only during the
/// drop), then the Activity Engine routes the drop to a provider that accepts drops.
struct NotchDrop {
    /// The drop tiles the shelf offers.
    enum Target: String, CaseIterable, Sendable {
        /// Keep on the File Shelf.
        case shelf
        /// Put onto the clipboard.
        case copy
        /// Send with AirDrop.
        case airDrop
    }

    enum Item {
        /// A file or folder.
        case file(URL)
        /// A file the source app writes on request, such as a photo from Photos or a mail attachment.
        case filePromise(NSFilePromiseReceiver)
        /// Image or PDF data without a file, such as an image dragged from some browsers.
        case contents(Data, UTType)
        /// A web link.
        case url(URL)
        case text(String)
    }

    var items: [Item]
    var target: Target
}

extension NotchDrop {
    /// More items than this in one drop are ignored.
    static let maxItems = 100
    /// Larger dropped text or data is ignored rather than kept in memory.
    static let maxTextLength = 1_000_000
    static let maxContentsSize = 100 * 1024 * 1024

    /// Data types read as `contents`, most preferred first.
    static let contentsTypes: [(NSPasteboard.PasteboardType, UTType)] = [
        (.png, .png),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), .jpeg),
        (.tiff, .tiff),
        (.pdf, .pdf),
    ]

    /// The drag types the notch registers for. A drag carrying none of them doesn't open the shelf.
    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, .string]
            + contentsTypes.map(\.0)
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    /// Whether the pasteboard carries anything a drop could use. Reads only the types.
    static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: acceptedTypes) != nil
    }

    /// Reads the dropped items, most specific first: files, then promised files, then image or PDF
    /// data, then web links, then text. Only the first kind found is used, so a file dragged from
    /// Finder isn't also kept as its name or icon.
    @MainActor
    static func items(from pasteboard: NSPasteboard) -> [Item] {
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if !fileURLs.isEmpty {
            return fileURLs.prefix(maxItems).map(Item.file)
        }

        let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        if !promises.isEmpty {
            return promises.prefix(maxItems).map(Item.filePromise)
        }

        for (type, utType) in contentsTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty, data.count <= maxContentsSize {
                return [.contents(data, utType)]
            }
        }

        let links = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? [])
            .filter(isWebURL)
        if !links.isEmpty {
            return links.prefix(maxItems).map(Item.url)
        }

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           text.count <= maxTextLength {
            return [.text(text)]
        }
        return []
    }

    /// Only web links are kept; other schemes (`file`, `javascript`, app URLs) are never opened from the shelf.
    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return url.host() != nil
    }
}

/// Decides which drop tile a drop landed on.
enum ShelfDropTargeting {
    /// The tile containing `location`, or `.shelf` when the drop lands elsewhere on the surface,
    /// so a hurried drop anywhere keeps the item.
    static func target(at location: CGPoint?, tileFrames: [NotchDrop.Target: CGRect]) -> NotchDrop.Target {
        guard let location else { return .shelf }
        return NotchDrop.Target.allCases.first { tileFrames[$0]?.contains(location) == true } ?? .shelf
    }
}
