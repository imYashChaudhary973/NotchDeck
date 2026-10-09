import Foundation
import UniformTypeIdentifiers

/// Where clipboard history is kept on this Mac.
@MainActor
protocol ClipboardStoring {
    func load() -> ClipboardHistory
    func save(_ history: ClipboardHistory)
    /// Writes a copied image. Returns its file name.
    func storeImage(_ data: Data, type: UTType, id: UUID) -> String?
    func imageURL(_ fileName: String) -> URL?
    func removeImage(_ fileName: String)
    /// Deletes images no entry refers to (left from a crash).
    func removeOrphanedImages(keeping fileNames: Set<String>)
    /// Deletes the history and every image.
    func removeAll()
}

/// `~/Library/Application Support/NotchDeck/Clipboard`: `history.json` and an `Images` directory,
/// readable only by the user.
@MainActor
final class ClipboardDirectoryStore: ClipboardStoring {
    let root: URL
    private let fileManager = FileManager.default

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "NotchDeck/Clipboard", directoryHint: .isDirectory)
    }

    init(root: URL = ClipboardDirectoryStore.defaultRoot) {
        self.root = root.standardizedFileURL
    }

    private var historyURL: URL { root.appending(path: "history.json") }
    private var imagesDirectory: URL { root.appending(path: "Images", directoryHint: .isDirectory) }

    func load() -> ClipboardHistory {
        guard let data = try? Data(contentsOf: historyURL),
              let history = try? JSONDecoder().decode(ClipboardHistory.self, from: data) else { return ClipboardHistory() }
        return history
    }

    func save(_ history: ClipboardHistory) {
        guard !history.isEmpty else {
            try? fileManager.removeItem(at: historyURL)
            return
        }
        guard createDirectory(root), let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: historyURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
    }

    func storeImage(_ data: Data, type: UTType, id: UUID) -> String? {
        guard createDirectory(imagesDirectory) else { return nil }
        let fileName = id.uuidString + "." + (type.preferredFilenameExtension ?? "png")
        let url = imagesDirectory.appending(path: fileName)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return fileName
    }

    func imageURL(_ fileName: String) -> URL? {
        guard Self.isSafeFileName(fileName) else { return nil }
        let url = imagesDirectory.appending(path: fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func removeImage(_ fileName: String) {
        guard Self.isSafeFileName(fileName) else { return }
        try? fileManager.removeItem(at: imagesDirectory.appending(path: fileName))
    }

    func removeOrphanedImages(keeping fileNames: Set<String>) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: imagesDirectory.path) else { return }
        for name in contents where !fileNames.contains(name) && Self.isSafeFileName(name) {
            try? fileManager.removeItem(at: imagesDirectory.appending(path: name))
        }
    }

    func removeAll() {
        try? fileManager.removeItem(at: historyURL)
        try? fileManager.removeItem(at: imagesDirectory)
    }

    /// Image names are `<UUID>.<extension>`; anything else (a path, "..") is refused.
    static func isSafeFileName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && UUID(uuidString: String(parts[0])) != nil && !parts[1].isEmpty
            && parts[1].allSatisfy { $0.isLetter || $0.isNumber }
    }

    private func createDirectory(_ url: URL) -> Bool {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return true
        } catch {
            return false
        }
    }
}
