import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares album artwork for the notch: decodes it off the main thread and scales it down, so a
/// multi-megabyte cover never sits in memory or in every activity update.
enum ArtworkLoader {
    /// Large enough for the 64 pt command-center artwork on a Retina display.
    static let maxPixelSize = 192

    static func thumbnail(from data: Data) async -> Data? {
        await Task.detached(priority: .utility) {
            makeThumbnail(from: data)
        }.value
    }

    /// Downloads artwork from the media app's own image CDN. Only HTTPS URLs on `allowedHosts`
    /// (and their subdomains) are fetched; nothing is cached or stored.
    static func download(_ url: URL, allowedHosts: [String]) async -> Data? {
        guard isAllowed(url, hosts: allowedHosts) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return await thumbnail(from: data)
    }

    static func isAllowed(_ url: URL, hosts: [String]) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    nonisolated static func makeThumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
