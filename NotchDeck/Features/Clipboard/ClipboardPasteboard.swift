import AppKit
import UniformTypeIdentifiers

/// Whether NotchDeck may read what other apps copy (macOS 15.4+ "Paste from Other Apps").
enum ClipboardAccess: Equatable, Sendable {
    /// Reading is allowed. Before macOS has ever asked, it asks once, on the first read.
    case allowed
    /// macOS asks on every read. NotchDeck doesn't read, so it never prompts on its own.
    case askEachTime
    case denied
}

@available(macOS 15.4, *)
extension ClipboardAccess {
    init(_ behavior: NSPasteboard.AccessBehavior) {
        switch behavior {
        case .alwaysAllow: self = .allowed
        // Never asked yet: the first read shows the system prompt (NotchDeck reads only right after the
        // user turns the feature on, so the prompt appears in context). Afterwards macOS reports `.ask`.
        case .default: self = .allowed
        case .ask: self = .askEachTime
        case .alwaysDeny: self = .denied
        @unknown default: self = .askEachTime
        }
    }
}

/// The general pasteboard as clipboard history sees it.
@MainActor
protocol ClipboardPasteboard: AnyObject {
    /// Increments whenever anything is copied. Reading it never triggers the privacy prompt.
    var changeCount: Int { get }
    var access: ClipboardAccess { get }
    /// The types on the clipboard, read without its contents.
    func types() -> [String]
    /// Reads the contents NotchDeck keeps.
    func snapshot() -> ClipboardCapture.Snapshot
}

@MainActor
final class SystemClipboardPasteboard: ClipboardPasteboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    var access: ClipboardAccess {
        if #available(macOS 15.4, *) {
            ClipboardAccess(pasteboard.accessBehavior)
        } else {
            .allowed
        }
    }

    func types() -> [String] {
        pasteboard.types?.map(\.rawValue) ?? []
    }

    /// Reads as little as possible: file references stop there; otherwise text (with RTF when present),
    /// and image, color or URL data only when there is no text.
    func snapshot() -> ClipboardCapture.Snapshot {
        var snapshot = ClipboardCapture.Snapshot()
        let types = Set(pasteboard.types ?? [])

        if types.contains(.fileURL) {
            snapshot.fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            if !snapshot.fileURLs.isEmpty { return snapshot }
        }

        if types.contains(.string) {
            snapshot.string = pasteboard.string(forType: .string)
            if types.contains(.rtf) {
                snapshot.rtf = pasteboard.data(forType: .rtf)
            }
            return snapshot
        }

        for (type, utType) in [(NSPasteboard.PasteboardType.png, UTType.png), (.tiff, .tiff)] where types.contains(type) {
            if let data = pasteboard.data(forType: type) {
                snapshot.imageData = data
                snapshot.imageType = utType
                return snapshot
            }
        }

        if types.contains(.color), let color = NSColor(from: pasteboard)?.usingColorSpace(.sRGB) {
            snapshot.color = ColorComponents(
                red: Double(color.redComponent),
                green: Double(color.greenComponent),
                blue: Double(color.blueComponent),
                alpha: Double(color.alphaComponent)
            )
            return snapshot
        }

        if types.contains(.URL) {
            snapshot.url = pasteboard.string(forType: .URL).flatMap(URL.init(string:))
        }
        return snapshot
    }
}
