import AppKit
import UniformTypeIdentifiers

/// Something NotchDeck puts on the clipboard at the user's request.
enum PasteboardPayload: Equatable, Sendable {
    case files([URL])
    case url(URL)
    /// Plain text, with rich text (RTF) when it was copied with formatting.
    case text(String, rtf: Data? = nil)
    /// Image or PDF data.
    case data(Data, UTType)
    case color(ColorComponents, text: String)
}

/// Writes to the general pasteboard. Writing never triggers the paste privacy alert.
@MainActor
protocol PasteboardWriting {
    /// Replaces the clipboard with `payload`. Returns the pasteboard's new change count.
    @discardableResult
    func write(_ payload: PasteboardPayload) -> Int
}

@MainActor
struct SystemPasteboardWriter: PasteboardWriting {
    var pasteboard: NSPasteboard = .general

    @discardableResult
    func write(_ payload: PasteboardPayload) -> Int {
        pasteboard.clearContents()
        switch payload {
        case .files(let urls):
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        case .url(let url):
            pasteboard.writeObjects([url as NSURL])
            pasteboard.setString(url.absoluteString, forType: .string)
        case .text(let string, let rtf):
            if let rtf {
                pasteboard.setData(rtf, forType: .rtf)
            }
            pasteboard.setString(string, forType: .string)
        case .data(let data, let type):
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        case .color(let color, let text):
            let nsColor = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
            pasteboard.writeObjects([nsColor])
            pasteboard.setString(text, forType: .string)
        }
        return pasteboard.changeCount
    }
}
