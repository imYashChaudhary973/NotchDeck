import Foundation

/// A file or folder the user dropped, referenced with a bookmark so it is found again after it is
/// moved or renamed. The file itself is never copied.
struct ShelfFileReference: Codable, Equatable, Sendable {
    var bookmark: Data
    /// Where the file was when it was last found.
    var path: String
    var name: String
    var isDirectory: Bool
    var typeIdentifier: String?
}

/// A file NotchDeck stored itself (a received file promise or dropped image data). It lives in the
/// shelf's storage directory and is deleted with its item.
struct ShelfStoredFile: Codable, Equatable, Sendable {
    /// Path relative to the storage directory.
    var relativePath: String
    var name: String
    var typeIdentifier: String?
}

/// What a shelf item holds.
enum ShelfItemContent: Codable, Equatable, Sendable {
    case file(ShelfFileReference)
    case storedFile(ShelfStoredFile)
    /// A promised file the source app is still writing. Never saved.
    case pending(name: String)
    case link(URL)
    case text(String)

    /// Identifies the same thing dropped twice. Nil for content that is always new.
    var duplicateKey: String? {
        switch self {
        case .file(let reference): "file:" + reference.path
        case .link(let url): "link:" + url.absoluteString
        case .text(let text): "text:" + text
        case .storedFile, .pending: nil
        }
    }

    /// The name shown for the item.
    var title: String {
        switch self {
        case .file(let reference): reference.name
        case .storedFile(let stored): stored.name
        case .pending(let name): name
        case .link(let url): ShelfText.linkTitle(url)
        case .text(let text): ShelfText.firstLine(of: text)
        }
    }

    /// Whether NotchDeck stored files for this item that must be deleted with it.
    var ownsFiles: Bool {
        switch self {
        case .storedFile, .pending: true
        case .file, .link, .text: false
        }
    }
}

/// How long a shelf item is kept.
enum ShelfRetention: Codable, Equatable, Sendable {
    /// Removed at this date.
    case until(Date)
    /// Kept until the user removes it.
    case pinned

    /// The longer of two retentions (pinned outlasts any date).
    static func longer(_ lhs: ShelfRetention, _ rhs: ShelfRetention) -> ShelfRetention {
        switch (lhs, rhs) {
        case (.pinned, _), (_, .pinned): .pinned
        case (.until(let a), .until(let b)): .until(max(a, b))
        }
    }
}

/// How long a new item stays on the shelf unless it is pinned.
enum ShelfLifetime: String, CaseIterable, Identifiable, Sendable {
    case oneHour
    case endOfDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour: "1 hour"
        case .endOfDay: "Until the end of the day"
        }
    }

    /// When an item added at `date` is removed.
    func expiry(from date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .oneHour:
            date.addingTimeInterval(3600)
        case .endOfDay:
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86_400)
        }
    }
}

struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var content: ShelfItemContent
    var addedAt: Date
    var retention: ShelfRetention

    init(id: UUID = UUID(), content: ShelfItemContent, addedAt: Date, retention: ShelfRetention) {
        self.id = id
        self.content = content
        self.addedAt = addedAt
        self.retention = retention
    }

    var isPinned: Bool { retention == .pinned }

    var isPending: Bool {
        if case .pending = content { true } else { false }
    }

    var expiresAt: Date? {
        if case .until(let date) = retention { date } else { nil }
    }

    func isExpired(at date: Date) -> Bool {
        expiresAt.map { $0 <= date } ?? false
    }
}

/// The items on the shelf, newest first, and the rules for adding, keeping and removing them.
/// A pure value type, so every rule is unit tested.
struct ShelfCollection: Equatable, Sendable {
    /// Beyond this, the oldest unpinned items make room for new ones.
    static let maxItems = 30

    private(set) var items: [ShelfItem]

    init(items: [ShelfItem] = []) {
        self.items = items
    }

    var isEmpty: Bool { items.isEmpty }

    func item(_ id: UUID) -> ShelfItem? {
        items.first { $0.id == id }
    }

    struct AddResult: Equatable, Sendable {
        /// The items now on the shelf for this drop, in shelf order. A duplicate is the existing item.
        var added: [ShelfItem]
        /// Items that left the shelf to make room (their stored files must be deleted).
        var removed: [ShelfItem]
    }

    /// Adds dropped items in front, in drop order. Something already on the shelf moves to the front
    /// instead of appearing twice; it keeps its pin and stays at least as long as the new item would.
    /// Beyond `maxItems`, the oldest unpinned items are removed.
    mutating func add(_ newItems: [ShelfItem]) -> AddResult {
        var addedIDs: [UUID] = []
        for item in newItems.reversed() {
            if let key = item.content.duplicateKey,
               let index = items.firstIndex(where: { $0.content.duplicateKey == key }) {
                var existing = items.remove(at: index)
                existing.content = item.content
                existing.addedAt = item.addedAt
                existing.retention = ShelfRetention.longer(existing.retention, item.retention)
                items.insert(existing, at: 0)
                addedIDs.removeAll { $0 == existing.id }
                addedIDs.insert(existing.id, at: 0)
            } else {
                items.insert(item, at: 0)
                addedIDs.insert(item.id, at: 0)
            }
        }

        var removed: [ShelfItem] = []
        while items.count > Self.maxItems, let index = items.lastIndex(where: { !$0.isPinned }) {
            removed.append(items.remove(at: index))
        }
        let remaining = Set(items.map(\.id))
        let added = addedIDs.filter(remaining.contains).compactMap(item)
        return AddResult(added: added, removed: removed)
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> ShelfItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    /// Removes every unpinned item ("Clear").
    mutating func removeUnpinned() -> [ShelfItem] {
        let removed = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        return removed
    }

    mutating func removeAll() -> [ShelfItem] {
        defer { items.removeAll() }
        return items
    }

    /// Removes items whose time is up.
    mutating func removeExpired(at date: Date) -> [ShelfItem] {
        let removed = items.filter { $0.isExpired(at: date) }
        items.removeAll { $0.isExpired(at: date) }
        return removed
    }

    @discardableResult
    mutating func setRetention(_ retention: ShelfRetention, for id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items[index].retention = retention
        return true
    }

    @discardableResult
    mutating func setContent(_ content: ShelfItemContent, for id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items[index].content = content
        return true
    }

    /// Adds an item right after another one (a second file from the same promise).
    mutating func insert(_ item: ShelfItem, after id: UUID) {
        let index = items.firstIndex { $0.id == id }.map { $0 + 1 } ?? 0
        items.insert(item, at: index)
    }

    /// The earliest time an item expires, if any will.
    var nextExpiry: Date? {
        items.compactMap(\.expiresAt).min()
    }
}

/// Display text for shelf items.
enum ShelfText {
    static let maxTitleLength = 60

    /// The first non-empty line, trimmed and shortened.
    static func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > maxTitleLength ? String(line.prefix(maxTitleLength - 1)) + "…" : line
    }

    /// Host and path, e.g. "apple.com/mac".
    static func linkTitle(_ url: URL) -> String {
        var host = url.host() ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let title = path.isEmpty ? host : host + "/" + path
        return title.count > maxTitleLength ? String(title.prefix(maxTitleLength - 1)) + "…" : title
    }
}
