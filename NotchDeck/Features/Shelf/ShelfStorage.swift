import Foundation

/// The result of looking for a referenced file.
enum ShelfFileResolution: Equatable, Sendable {
    /// The file is there. `updated` is set when it moved or its bookmark needed refreshing.
    case available(URL, updated: ShelfFileReference?)
    /// The file was deleted, moved to the Trash or is on a volume that isn't mounted.
    case missing
}

/// Where the shelf keeps its list of items and the few files it stores itself.
///
/// Dropped files are referenced with bookmarks and never copied. Only content without a file of its
/// own (a received file promise, dropped image data) is written, each item in its own directory.
@MainActor
protocol ShelfStoring {
    func loadItems() -> [ShelfItem]
    func saveItems(_ items: [ShelfItem])
    /// Validates a dropped file and references it. Nil unless it is an existing, readable file or folder.
    func makeReference(to url: URL) -> ShelfFileReference?
    func resolve(_ reference: ShelfFileReference) -> ShelfFileResolution
    /// Writes dropped data as a file belonging to the item.
    func store(_ data: Data, name: String, for id: UUID) -> ShelfStoredFile?
    /// The item's directory, created empty, for a promised file to be written into.
    func promiseDirectory(for id: UUID) -> URL?
    /// Describes a file in the storage directory as belonging to the item, moving it into the item's
    /// directory if it is in another one.
    func adopt(_ url: URL, for id: UUID) -> ShelfStoredFile?
    /// The stored file, if it still exists.
    func url(for stored: ShelfStoredFile) -> URL?
    func removeFiles(for id: UUID)
    /// Deletes stored files no listed item owns (left from an unfinished promise or a crash).
    func removeOrphanedFiles(keeping ids: Set<UUID>)
}

@MainActor
final class ShelfDirectoryStorage: ShelfStoring {
    let root: URL
    private let fileManager = FileManager.default

    /// `~/Library/Application Support/NotchDeck/Shelf`.
    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "NotchDeck/Shelf", directoryHint: .isDirectory)
    }

    init(root: URL = ShelfDirectoryStorage.defaultRoot) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    private var indexURL: URL { root.appending(path: "shelf.json") }
    private var itemsDirectory: URL { root.appending(path: "Items", directoryHint: .isDirectory) }

    private func itemDirectory(_ id: UUID) -> URL {
        itemsDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    // MARK: Index

    func loadItems() -> [ShelfItem] {
        guard let data = try? Data(contentsOf: indexURL),
              let items = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return [] }
        return items.filter { !$0.isPending }
    }

    func saveItems(_ items: [ShelfItem]) {
        let kept = items.filter { !$0.isPending }
        guard !kept.isEmpty else {
            try? fileManager.removeItem(at: indexURL)
            return
        }
        guard createDirectory(root), let data = try? JSONEncoder().encode(kept) else { return }
        try? data.write(to: indexURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
    }

    // MARK: References

    func makeReference(to url: URL) -> ShelfFileReference? {
        guard url.isFileURL else { return nil }
        // Bookmarks resolve to real paths, so compare real paths.
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        // A file NotchDeck stored is owned by its item; referencing it again would leave a dangling item.
        guard !isInside(url, root), !Self.isInTrash(url), fileManager.fileExists(atPath: url.path) else { return nil }
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isReadableKey, .nameKey, .contentTypeKey]),
              values.isReadable == true,
              let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return nil }
        return ShelfFileReference(
            bookmark: bookmark,
            path: url.path,
            name: values.name ?? url.lastPathComponent,
            isDirectory: values.isDirectory == true && values.isPackage != true,
            typeIdentifier: values.contentType?.identifier
        )
    }

    func resolve(_ reference: ShelfFileReference) -> ShelfFileResolution {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: reference.bookmark,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return .missing }
        let url = resolved.standardizedFileURL.resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: url.path), !Self.isInTrash(url) else { return .missing }
        guard isStale || url.path != reference.path else { return .available(url, updated: nil) }

        var updated = reference
        updated.path = url.path
        updated.name = url.lastPathComponent
        if isStale, let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            updated.bookmark = bookmark
        }
        return .available(url, updated: updated)
    }

    /// Moving a file to the Trash keeps it findable by its bookmark; for the shelf it is gone.
    static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains(".Trash") || url.pathComponents.contains(".Trashes")
    }

    // MARK: Stored files

    func store(_ data: Data, name: String, for id: UUID) -> ShelfStoredFile? {
        let directory = itemDirectory(id)
        guard createDirectory(directory) else { return nil }
        let url = directory.appending(path: Self.safeFileName(name))
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return storedFile(at: url, in: directory)
    }

    func promiseDirectory(for id: UUID) -> URL? {
        let directory = itemDirectory(id)
        return createDirectory(directory) ? directory : nil
    }

    func adopt(_ url: URL, for id: UUID) -> ShelfStoredFile? {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        guard isInside(url, itemsDirectory) else { return nil }
        let directory = itemDirectory(id)
        if isInside(url, directory) {
            return storedFile(at: url, in: directory)
        }
        guard createDirectory(directory) else { return nil }
        let destination = directory.appending(path: url.lastPathComponent)
        guard (try? fileManager.moveItem(at: url, to: destination)) != nil else { return nil }
        return storedFile(at: destination, in: directory)
    }

    func url(for stored: ShelfStoredFile) -> URL? {
        let url = root.appending(path: stored.relativePath).standardizedFileURL
        guard isInside(url, itemsDirectory), fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func removeFiles(for id: UUID) {
        try? fileManager.removeItem(at: itemDirectory(id))
    }

    func removeOrphanedFiles(keeping ids: Set<UUID>) {
        guard let contents = try? fileManager.contentsOfDirectory(at: itemsDirectory, includingPropertiesForKeys: nil) else { return }
        // Only directories named after an item are ever deleted.
        for url in contents {
            guard let id = UUID(uuidString: url.lastPathComponent), !ids.contains(id) else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func storedFile(at url: URL, in directory: URL) -> ShelfStoredFile? {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        guard isInside(url, directory) else { return nil }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        return ShelfStoredFile(
            relativePath: String(url.path.dropFirst(root.path.count + 1)),
            name: url.lastPathComponent,
            typeIdentifier: type?.identifier
        )
    }

    // MARK: Helpers

    /// Creates a directory only the user can read.
    private func createDirectory(_ url: URL) -> Bool {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return true
        } catch {
            return false
        }
    }

    private func isInside(_ url: URL, _ directory: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().path
            .hasPrefix(directory.standardizedFileURL.resolvingSymlinksInPath().path + "/")
    }

    /// A name that can't escape its directory: no path separators, no leading dots, a bounded length.
    static func safeFileName(_ name: String) -> String {
        var cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        if cleaned.count > 120 {
            let pathExtension = (cleaned as NSString).pathExtension
            let suffix = pathExtension.isEmpty || pathExtension.count > 10 ? "" : "." + pathExtension
            cleaned = String(cleaned.prefix(120 - suffix.count)) + suffix
        }
        return cleaned.isEmpty ? "Item" : cleaned
    }
}
