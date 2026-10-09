import Foundation

/// What kind of thing was copied. Decides the icon and how an entry is drawn.
enum ClipboardKind: String, Codable, Sendable {
    case text
    case code
    case link
    case color
    case image
    case files

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        case .color: "paintpalette"
        case .image: "photo"
        case .files: "doc"
        }
    }
}

/// An image kept in the history's directory.
struct ClipboardImage: Codable, Equatable, Sendable {
    var fileName: String
    var typeIdentifier: String
    var pixelWidth: Int
    var pixelHeight: Int
}

/// Copied content NotchDeck keeps.
enum ClipboardContent: Codable, Equatable, Sendable {
    /// Text, with its rich text (RTF) when it was copied with formatting and is small.
    case text(String, rtf: Data?)
    case link(URL)
    /// A recognized color, and the text it was copied as (e.g. "#FF8800").
    case color(ColorComponents, text: String)
    case image(ClipboardImage)
    /// References to files. Only their paths are kept; the files are never read.
    case files([URL])
}

/// Where a copy came from: the app that was frontmost when the clipboard changed.
struct ClipboardSource: Equatable, Sendable {
    var bundleID: String?
    var name: String?
}

struct ClipboardEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var content: ClipboardContent
    var kind: ClipboardKind
    /// Identifies identical content (a SHA-256 digest), so the same copy is kept once.
    var fingerprint: String
    var copiedAt: Date
    var sourceBundleID: String?
    var sourceName: String?
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        content: ClipboardContent,
        kind: ClipboardKind,
        fingerprint: String,
        copiedAt: Date,
        source: ClipboardSource? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.content = content
        self.kind = kind
        self.fingerprint = fingerprint
        self.copiedAt = copiedAt
        self.sourceBundleID = source?.bundleID
        self.sourceName = source?.name
        self.isPinned = isPinned
    }

    /// One line describing the entry.
    var preview: String {
        switch content {
        case .text(let text, _): ClipboardText.firstLine(of: text)
        case .link(let url): url.absoluteString
        case .color(_, let text): text
        case .image(let image): "Image · \(image.pixelWidth) × \(image.pixelHeight)"
        case .files(let urls): urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        }
    }

    /// What search matches against: the content and the app it came from.
    var searchableText: String {
        let text = switch content {
        case .text(let text, _): text
        case .link(let url): url.absoluteString
        case .color(_, let text): text
        case .image: "Image"
        case .files(let urls): urls.map(\.lastPathComponent).joined(separator: " ")
        }
        return sourceName.map { text + "\n" + $0 } ?? text
    }
}

/// The clipboard history, newest first, and its rules: deduplication, limits, retention, pins and
/// search. A pure value type, so every rule is unit tested.
struct ClipboardHistory: Codable, Equatable, Sendable {
    struct Limits: Equatable, Sendable {
        /// Most unpinned entries kept. Pinned entries don't count and are never removed by limits.
        var maxEntries: Int
        /// Unpinned entries older than this are forgotten. Nil keeps them until the limit removes them.
        var retention: TimeInterval?
    }

    private(set) var entries: [ClipboardEntry] = []

    init(entries: [ClipboardEntry] = []) {
        self.entries = entries
    }

    var isEmpty: Bool { entries.isEmpty }

    func entry(_ id: UUID) -> ClipboardEntry? {
        entries.first { $0.id == id }
    }

    func contains(fingerprint: String) -> Bool {
        entries.contains { $0.fingerprint == fingerprint }
    }

    /// Adds a copy at the top. Copying something already in the history moves that entry to the top
    /// (keeping its pin) instead of adding it twice. Returns entries whose stored data is no longer
    /// used (removed by the limits, or replaced by the new copy).
    mutating func record(_ entry: ClipboardEntry, limits: Limits, now: Date) -> [ClipboardEntry] {
        var unused: [ClipboardEntry] = []
        var entry = entry
        if let index = entries.firstIndex(where: { $0.fingerprint == entry.fingerprint }) {
            let existing = entries.remove(at: index)
            entry = ClipboardEntry(
                id: existing.id,
                content: entry.content,
                kind: entry.kind,
                fingerprint: entry.fingerprint,
                copiedAt: entry.copiedAt,
                source: ClipboardSource(bundleID: entry.sourceBundleID, name: entry.sourceName),
                isPinned: existing.isPinned || entry.isPinned
            )
            if existing.content != entry.content { unused.append(existing) }
        }
        entries.insert(entry, at: 0)
        return unused + enforce(limits, now: now)
    }

    /// Moves an existing entry to the top as if it were just copied. Returns false if there is none.
    @discardableResult
    mutating func moveToTop(fingerprint: String, at date: Date, source: ClipboardSource? = nil) -> Bool {
        guard let index = entries.firstIndex(where: { $0.fingerprint == fingerprint }) else { return false }
        var entry = entries.remove(at: index)
        entry.copiedAt = date
        if let source {
            entry.sourceBundleID = source.bundleID
            entry.sourceName = source.name
        }
        entries.insert(entry, at: 0)
        return true
    }

    /// Applies the limits: forgets unpinned entries past the retention, then the oldest unpinned
    /// entries beyond the maximum. Returns the removed entries.
    mutating func enforce(_ limits: Limits, now: Date) -> [ClipboardEntry] {
        var kept: [ClipboardEntry] = []
        var removed: [ClipboardEntry] = []
        var unpinnedKept = 0
        let cutoff = limits.retention.map { now.addingTimeInterval(-$0) }
        for entry in entries {
            let isTooOld = cutoff.map { entry.copiedAt < $0 } ?? false
            if entry.isPinned {
                kept.append(entry)
            } else if !isTooOld, unpinnedKept < max(limits.maxEntries, 0) {
                unpinnedKept += 1
                kept.append(entry)
            } else {
                removed.append(entry)
            }
        }
        entries = kept
        return removed
    }

    /// When the oldest unpinned entry passes the retention, if any will.
    func nextRetentionExpiry(_ retention: TimeInterval?) -> Date? {
        guard let retention else { return nil }
        return entries.filter { !$0.isPinned }.map(\.copiedAt).min().map { $0.addingTimeInterval(retention) }
    }

    @discardableResult
    mutating func setPinned(_ isPinned: Bool, for id: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries[index].isPinned = isPinned
        return true
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> ClipboardEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    /// Removes unpinned entries, or every entry. Returns the removed entries.
    mutating func clear(includingPinned: Bool) -> [ClipboardEntry] {
        let removed = entries.filter { includingPinned || !$0.isPinned }
        entries.removeAll { includingPinned || !$0.isPinned }
        return removed
    }

    /// Entries matching every word of the query (ignoring case and diacritics), newest first.
    func search(_ query: String) -> [ClipboardEntry] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return entries }
        return entries.filter { entry in
            let text = entry.searchableText
            return terms.allSatisfy { text.localizedStandardContains($0) }
        }
    }

    /// What the notch lists: pinned entries first, then the most recent, up to `limit`.
    func featured(limit: Int) -> [ClipboardEntry] {
        Array((entries.filter(\.isPinned) + entries.filter { !$0.isPinned }).prefix(limit))
    }
}

/// Display text for clipboard entries.
enum ClipboardText {
    static let maxPreviewLength = 120

    /// The first non-empty line, trimmed and shortened.
    static func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > maxPreviewLength ? String(line.prefix(maxPreviewLength - 1)) + "…" : line
    }

    /// A short age such as "now", "5m", "3h" or "2d".
    static func age(of date: Date, at now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }
}
