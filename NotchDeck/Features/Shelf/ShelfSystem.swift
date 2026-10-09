import AppKit
import QuickLookThumbnailing
import QuickLookUI
import UniformTypeIdentifiers

/// Makes small previews of files.
@MainActor
protocol ThumbnailGenerating {
    /// A small PNG preview of the file (its icon when there is no better preview), or nil.
    func thumbnail(for url: URL) async -> Data?
}

/// Quick Look thumbnails, rendered off the main thread at notch size so full-size images are never
/// decoded for the notch.
struct QuickLookThumbnailGenerator: ThumbnailGenerating {
    /// Points; rendered at 2× for Retina.
    nonisolated static let size = CGSize(width: 48, height: 48)

    func thumbnail(for url: URL) async -> Data? {
        await Self.render(url)
    }

    private nonisolated static func render(_ url: URL) async -> Data? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .all)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: representation.cgImage).representation(using: .png, properties: [:])
    }
}

/// Something the shelf sends with AirDrop.
enum ShelfShareItem: Equatable, Sendable {
    case file(URL)
    case url(URL)
    case text(String)
    case image(Data)
}

/// System actions the shelf performs on behalf of the user.
@MainActor
protocol ShelfSystemActions {
    func reveal(_ urls: [URL])
    func open(_ url: URL)
    func quickLook(_ urls: [URL])
    /// Opens the AirDrop window for the items. Returns false if AirDrop can't send them.
    func airDrop(_ items: [ShelfShareItem]) -> Bool
}

@MainActor
final class SystemShelfActions: NSObject, ShelfSystemActions, QLPreviewPanelDataSource {
    private var previewURLs: [URL] = []

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func quickLook(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        previewURLs = urls
        // The notch panel never becomes key, so Quick Look gets its data source directly.
        NSApp.activate()
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { previewURLs.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let url: URL? = MainActor.assumeIsolated {
            previewURLs.indices.contains(index) ? previewURLs[index] : nil
        }
        return url.map { $0 as NSURL }
    }

    func airDrop(_ items: [ShelfShareItem]) -> Bool {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return false }
        let objects: [Any] = items.compactMap { item in
            switch item {
            case .file(let url), .url(let url): url as NSURL
            case .text(let text): text as NSString
            case .image(let data): NSImage(data: data)
            }
        }
        guard !objects.isEmpty, service.canPerform(withItems: objects) else { return false }
        NSApp.activate()
        service.perform(withItems: objects)
        return true
    }
}
