import AppKit
import UniformTypeIdentifiers

/// The File Shelf: a temporary holding area for files, links and text dropped on the notch.
///
/// Dropped files are referenced, never copied. Items are kept for a while (an hour by default),
/// for the rest of the day, or until removed when pinned. The shelf is listed in the command center,
/// where items can be dragged out into other apps, previewed, copied, revealed or shared. It also
/// handles the other drop tiles: Copy (onto the clipboard) and AirDrop.
///
/// Nothing polls: the provider wakes only when the next item expires.
@MainActor
final class ShelfProvider: ActivityProvider {
    let source = ActivitySource(rawValue: "shelf")
    static let itemsActivityID = "items"
    static let confirmationActivityID = "confirmation"
    /// Things put aside on purpose lead the command center: above paused music (22) and Quick Actions (20).
    static let priority = ActivityPriority(rawValue: 25)
    /// A drop's confirmation briefly takes the notch, then leaves on its own.
    static let confirmationDuration: TimeInterval = 2.5

    enum ItemAction: String {
        case quickLook, open, copy, reveal, keepHour, keepToday, pin, unpin, remove
    }

    enum ActionID {
        /// Removes unpinned items.
        static let clear = "clear"
    }

    private(set) var collection = ShelfCollection()
    /// Items whose file was missing when last checked.
    private(set) var missingIDs: Set<UUID> = []

    private var publisher: ActivityPublisher?
    private var thumbnails: [UUID: Data] = [:]
    private var thumbnailAttempts: Set<UUID> = []
    private var thumbnailTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var isDisplayed = false
    /// Thumbnails are made only once the shelf has been on screen.
    private var hasBeenDisplayed = false

    private let storage: any ShelfStoring
    private let thumbnailer: any ThumbnailGenerating
    private let system: any ShelfSystemActions
    private let pasteboard: any PasteboardWriting
    private let lifetime: () -> ShelfLifetime
    private let now: () -> Date
    private let calendar: Calendar
    private let schedulesExpiry: Bool
    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// - Parameters:
    ///   - lifetime: How long new items are kept (a setting).
    ///   - schedulesExpiry: When `false`, items expire only when `expireItems()` is called (tests).
    init(
        storage: any ShelfStoring,
        thumbnailer: any ThumbnailGenerating = QuickLookThumbnailGenerator(),
        system: any ShelfSystemActions,
        pasteboard: any PasteboardWriting = SystemPasteboardWriter(),
        lifetime: @escaping () -> ShelfLifetime = { .oneHour },
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .current,
        schedulesExpiry: Bool = true
    ) {
        self.storage = storage
        self.thumbnailer = thumbnailer
        self.system = system
        self.pasteboard = pasteboard
        self.lifetime = lifetime
        self.now = now
        self.calendar = calendar
        self.schedulesExpiry = schedulesExpiry
    }

    // MARK: ActivityProvider

    var acceptsDrops: Bool { true }

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
        collection = ShelfCollection(items: storage.loadItems())
        collection.removeExpired(at: now()).forEach(cleanUp)
        storage.removeOrphanedFiles(keeping: Set(collection.items.map(\.id)))
        checkFiles()
        changed()
    }

    func stop() {
        expiryTask?.cancel()
        expiryTask = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        publisher = nil
        isDisplayed = false
        hasBeenDisplayed = false
    }

    func handleDrop(_ drop: NotchDrop) -> Bool {
        switch drop.target {
        case .shelf: keep(drop.items)
        case .copy: copy(drop.items)
        case .airDrop: airDrop(drop.items)
        }
    }

    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
        if actionID == ActionID.clear {
            collection.removeUnpinned().forEach(cleanUp)
            changed()
            return
        }
        guard let (name, itemID) = CollectionContent.itemAction(from: actionID),
              let action = ItemAction(rawValue: name),
              let id = UUID(uuidString: itemID),
              let item = collection.item(id) else { return }

        switch action {
        case .quickLook:
            if let url = availableURL(of: item) { system.quickLook([url]) }
        case .open:
            if case .link(let url) = item.content {
                system.open(url)
            } else if let url = availableURL(of: item) {
                system.open(url)
            }
        case .copy:
            if let payload = pasteboardPayload(for: item) { pasteboard.write(payload) }
        case .reveal:
            if let url = availableURL(of: item) { system.reveal([url]) }
        case .keepHour:
            setRetention(.until(ShelfLifetime.oneHour.expiry(from: now(), calendar: calendar)), for: id)
        case .keepToday:
            setRetention(.until(ShelfLifetime.endOfDay.expiry(from: now(), calendar: calendar)), for: id)
        case .pin:
            setRetention(.pinned, for: id)
        case .unpin:
            setRetention(.until(lifetime().expiry(from: now(), calendar: calendar)), for: id)
        case .remove:
            if let removed = collection.remove(id) { cleanUp(removed) }
            changed()
        }
    }

    func displayedActivitiesChanged(_ ids: Set<NotchActivity.ID>) {
        let displayed = ids.contains(Self.itemsActivityID)
        let appeared = displayed && !isDisplayed
        isDisplayed = displayed
        guard appeared else { return }
        hasBeenDisplayed = true
        // Files may have moved or been deleted since they were dropped; check whenever the shelf comes into view.
        if checkFiles() { publish() }
        loadThumbnails()
    }

    // MARK: Commands

    /// Removes every item, pinned or not, and deletes everything the shelf stored. Used when the
    /// feature is turned off, so it also works while the provider isn't running.
    func removeAll() {
        collection.removeAll().forEach(cleanUp)
        storage.removeOrphanedFiles(keeping: [])
        storage.saveItems([])
        missingIDs.removeAll()
        if publisher != nil { changed() }
    }

    /// Removes items whose time is up. Called by the scheduled wake-up, or directly in tests.
    func expireItems() {
        let expired = collection.removeExpired(at: now())
        guard !expired.isEmpty else {
            scheduleExpiry()
            return
        }
        expired.forEach(cleanUp)
        changed()
    }

    // MARK: Drops

    private func keep(_ dropped: [NotchDrop.Item]) -> Bool {
        let date = now()
        let retention = ShelfRetention.until(lifetime().expiry(from: date, calendar: calendar))
        var newItems: [ShelfItem] = []
        var promises: [UUID: NSFilePromiseReceiver] = [:]

        for item in dropped.prefix(NotchDrop.maxItems) {
            let id = UUID()
            let content: ShelfItemContent?
            switch item {
            case .file(let url):
                content = storage.makeReference(to: url).map(ShelfItemContent.file)
            case .filePromise(let receiver):
                content = .pending(name: receiver.fileNames.first ?? "File")
                promises[id] = receiver
            case .contents(let data, let type):
                content = storage.store(data, name: Self.fileName(for: type, at: date), for: id).map(ShelfItemContent.storedFile)
            case .url(let url):
                content = NotchDrop.isWebURL(url) ? .link(url) : nil
            case .text(let text):
                let isBlank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                content = isBlank || text.count > NotchDrop.maxTextLength ? nil : .text(text)
            }
            if let content {
                newItems.append(ShelfItem(id: id, content: content, addedAt: date, retention: retention))
            }
        }
        guard !newItems.isEmpty else { return false }

        let result = collection.add(newItems)
        result.removed.forEach(cleanUp)
        let kept = Set(result.added.map(\.id))
        for (id, receiver) in promises where kept.contains(id) {
            receive(receiver, for: id)
        }
        changed()
        guard !result.added.isEmpty else { return false }
        confirm("Added to Shelf", subtitle: Self.summary(result.added.map(\.content.title)), symbol: "tray.and.arrow.down.fill")
        return true
    }

    private func copy(_ dropped: [NotchDrop.Item]) -> Bool {
        guard let payload = Self.pasteboardPayload(for: dropped) else { return false }
        pasteboard.write(payload)
        confirm("Copied", subtitle: Self.summary(of: dropped), symbol: "doc.on.doc.fill")
        return true
    }

    private func airDrop(_ dropped: [NotchDrop.Item]) -> Bool {
        let items: [ShelfShareItem] = dropped.compactMap { item in
            switch item {
            case .file(let url): FileManager.default.fileExists(atPath: url.path) ? .file(url) : nil
            case .url(let url): NotchDrop.isWebURL(url) ? .url(url) : nil
            case .text(let text): .text(text)
            case .contents(let data, let type): type.conforms(to: .image) || type == .pdf ? .image(data) : nil
            case .filePromise: nil
            }
        }
        return !items.isEmpty && system.airDrop(items)
    }

    /// What Copy puts on the clipboard: files if any, otherwise image data, a link or text.
    static func pasteboardPayload(for items: [NotchDrop.Item]) -> PasteboardPayload? {
        var files: [URL] = []
        var contents: (Data, UTType)?
        var link: URL?
        var text: String?
        for item in items {
            switch item {
            case .file(let url) where FileManager.default.fileExists(atPath: url.path): files.append(url)
            case .contents(let data, let type): contents = contents ?? (data, type)
            case .url(let url) where NotchDrop.isWebURL(url): link = link ?? url
            case .text(let string): text = text ?? string
            default: break
            }
        }
        if !files.isEmpty { return .files(files) }
        if let contents { return .data(contents.0, contents.1) }
        if let link { return .url(link) }
        if let text { return .text(text) }
        return nil
    }

    // MARK: File promises

    private func receive(_ receiver: NSFilePromiseReceiver, for id: UUID) {
        guard let directory = storage.promiseDirectory(for: id) else {
            promiseReceived(nil, for: id)
            return
        }
        receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
            let received: URL? = error == nil ? url : nil
            Task { @MainActor in self?.promiseReceived(received, for: id) }
        }
    }

    /// The source app finished writing a promised file (or failed: `url` is nil).
    private func promiseReceived(_ url: URL?, for id: UUID) {
        guard let item = collection.item(id) else {
            // Removed or cleared while the file was being written.
            storage.removeFiles(for: id)
            return
        }
        if item.isPending {
            if let url, let stored = storage.adopt(url, for: id) {
                collection.setContent(.storedFile(stored), for: id)
            } else {
                collection.remove(id)
                storage.removeFiles(for: id)
            }
        } else if let url {
            // One promise can deliver several files; each becomes its own item.
            let extra = ShelfItem(content: .pending(name: url.lastPathComponent), addedAt: item.addedAt, retention: item.retention)
            guard let stored = storage.adopt(url, for: extra.id) else { return }
            var adopted = extra
            adopted.content = .storedFile(stored)
            collection.insert(adopted, after: id)
        } else {
            return
        }
        changed()
        loadThumbnails()
    }

    // MARK: Items

    private func setRetention(_ retention: ShelfRetention, for id: UUID) {
        collection.setRetention(retention, for: id)
        changed()
    }

    /// The item's file, if it is still there. Finding it missing updates the shelf.
    private func availableURL(of item: ShelfItem) -> URL? {
        switch item.content {
        case .file(let reference):
            switch storage.resolve(reference) {
            case .available(let url, let updated):
                if let updated { collection.setContent(.file(updated), for: item.id) }
                if missingIDs.remove(item.id) != nil || updated != nil { changed() }
                return url
            case .missing:
                if missingIDs.insert(item.id).inserted { publish() }
                return nil
            }
        case .storedFile(let stored):
            guard let url = storage.url(for: stored) else {
                if missingIDs.insert(item.id).inserted { publish() }
                return nil
            }
            return url
        case .pending, .link, .text:
            return nil
        }
    }

    private func pasteboardPayload(for item: ShelfItem) -> PasteboardPayload? {
        switch item.content {
        case .file, .storedFile: availableURL(of: item).map { .files([$0]) }
        case .link(let url): .url(url)
        case .text(let text): .text(text)
        case .pending: nil
        }
    }

    /// Looks for every referenced file. Returns whether anything changed.
    @discardableResult
    private func checkFiles() -> Bool {
        var changedAny = false
        for item in collection.items {
            var isMissing = false
            switch item.content {
            case .file(let reference):
                switch storage.resolve(reference) {
                case .available(_, let updated):
                    if let updated {
                        collection.setContent(.file(updated), for: item.id)
                        changedAny = true
                    }
                case .missing:
                    isMissing = true
                }
            case .storedFile(let stored):
                isMissing = storage.url(for: stored) == nil
            case .pending, .link, .text:
                break
            }
            let wasMissing = missingIDs.contains(item.id)
            if isMissing != wasMissing {
                if isMissing { missingIDs.insert(item.id) } else { missingIDs.remove(item.id) }
                changedAny = true
            }
        }
        if changedAny { storage.saveItems(collection.items) }
        return changedAny
    }

    private func cleanUp(_ item: ShelfItem) {
        if item.content.ownsFiles { storage.removeFiles(for: item.id) }
        thumbnails[item.id] = nil
        thumbnailAttempts.remove(item.id)
        missingIDs.remove(item.id)
    }

    /// Makes each item's thumbnail once, after the shelf has been on screen.
    private func loadThumbnails() {
        guard hasBeenDisplayed, thumbnailTask == nil else { return }
        let pending = collection.items.compactMap { item -> (UUID, URL)? in
            guard !thumbnailAttempts.contains(item.id), !missingIDs.contains(item.id) else { return nil }
            let url: URL? = switch item.content {
            case .file(let reference): URL(fileURLWithPath: reference.path)
            case .storedFile(let stored): storage.url(for: stored)
            case .pending, .link, .text: nil
            }
            return url.map { (item.id, $0) }
        }
        guard !pending.isEmpty else { return }
        pending.forEach { thumbnailAttempts.insert($0.0) }
        thumbnailTask = Task { [weak self, thumbnailer] in
            for (id, url) in pending {
                guard !Task.isCancelled else { return }
                let data = await thumbnailer.thumbnail(for: url)
                guard let self, !Task.isCancelled else { return }
                if let data, self.collection.item(id) != nil {
                    self.thumbnails[id] = data
                    self.publish()
                }
            }
            self?.thumbnailTask = nil
            self?.loadThumbnails()
        }
    }

    // MARK: Publishing

    private func changed() {
        storage.saveItems(collection.items)
        publish()
        scheduleExpiry()
    }

    private func publish() {
        guard let publisher else { return }
        if let activity = itemsActivity() {
            publisher.publish(activity)
        } else {
            publisher.withdraw(id: Self.itemsActivityID)
        }
    }

    private func confirm(_ title: String, subtitle: String?, symbol: String) {
        publisher?.publish(NotchActivity(
            id: Self.confirmationActivityID,
            source: source,
            kind: .shelf,
            priority: .timeSensitive,
            title: title,
            subtitle: subtitle,
            startedAt: now(),
            expiresAt: now().addingTimeInterval(Self.confirmationDuration),
            presentation: ActivityPresentation(
                symbolName: symbol,
                accent: .purple,
                compactAccessory: .symbol("checkmark"),
                statusText: title,
                revealsOnUpdate: true
            )
        ))
    }

    private func itemsActivity() -> NotchActivity? {
        guard !collection.isEmpty else { return nil }
        let items = collection.items.map(collectionItem)
        let count = collection.items.count
        let hasUnpinned = collection.items.contains { !$0.isPinned }
        return NotchActivity(
            id: Self.itemsActivityID,
            source: source,
            kind: .shelf,
            priority: Self.priority,
            placement: .commandCenter,
            title: "Shelf",
            subtitle: count == 1 ? "1 item · drag out to use" : "\(count) items · drag out to use",
            presentation: ActivityPresentation(
                symbolName: "tray.full.fill",
                accent: .purple,
                content: .collection(CollectionContent(layout: .tiles, items: items))
            ),
            actions: hasUnpinned ? [ActivityAction(id: ActionID.clear, title: "Clear Unpinned", systemImage: "trash")] : []
        )
    }

    private func collectionItem(_ item: ShelfItem) -> CollectionContent.Item {
        let itemID = item.id.uuidString
        func actionID(_ action: ItemAction) -> ActivityAction.ID {
            CollectionContent.actionID(action.rawValue, item: itemID)
        }
        func action(_ action: ItemAction, _ title: String, _ image: String, destructive: Bool = false) -> ActivityAction {
            ActivityAction(id: actionID(action), title: title, systemImage: image, isDestructive: destructive)
        }
        let remove = action(.remove, "Remove from Shelf", "xmark", destructive: true)
        let keep = item.isPinned
            ? [action(.unpin, "Unpin", "pin.slash")]
            : [action(.keepHour, "Keep for 1 Hour", "clock"), action(.keepToday, "Keep Until Tonight", "moon"), action(.pin, "Pin", "pin")]
        let retention = retentionText(item)
        let title = item.content.title

        switch item.content {
        case .file, .storedFile:
            if missingIDs.contains(item.id) {
                return CollectionContent.Item(
                    id: itemID, title: title, subtitle: "Missing", symbolName: "exclamationmark.triangle",
                    isPinned: item.isPinned, isUnavailable: true, menuActions: [remove]
                )
            }
            let (url, isDirectory, typeIdentifier) = fileInfo(item)
            return CollectionContent.Item(
                id: itemID,
                title: title,
                subtitle: [Self.kindDescription(isDirectory: isDirectory, typeIdentifier: typeIdentifier), retention].joined(separator: " · "),
                symbolName: isDirectory ? "folder.fill" : "doc.fill",
                thumbnail: thumbnails[item.id],
                isPinned: item.isPinned,
                payload: url.map(CollectionContent.Payload.file),
                primaryActionID: actionID(.quickLook),
                menuActions: [
                    action(.quickLook, "Quick Look", "eye"),
                    action(.open, "Open", "arrow.up.forward.app"),
                    action(.copy, "Copy", "doc.on.doc"),
                    action(.reveal, "Show in Finder", "folder"),
                ] + keep + [remove]
            )
        case .pending:
            return CollectionContent.Item(
                id: itemID, title: title, subtitle: "Receiving…", symbolName: "arrow.down.circle",
                isUnavailable: true, menuActions: [remove]
            )
        case .link(let url):
            return CollectionContent.Item(
                id: itemID,
                title: title,
                subtitle: ["Link", retention].joined(separator: " · "),
                symbolName: "link",
                isPinned: item.isPinned,
                payload: .url(url),
                primaryActionID: actionID(.open),
                menuActions: [action(.open, "Open", "safari"), action(.copy, "Copy Link", "doc.on.doc")] + keep + [remove]
            )
        case .text(let text):
            return CollectionContent.Item(
                id: itemID,
                title: title,
                subtitle: ["Text", retention].joined(separator: " · "),
                symbolName: "text.alignleft",
                isPinned: item.isPinned,
                payload: .text(text),
                primaryActionID: actionID(.copy),
                menuActions: [action(.copy, "Copy", "doc.on.doc")] + keep + [remove]
            )
        }
    }

    private func fileInfo(_ item: ShelfItem) -> (URL?, Bool, String?) {
        switch item.content {
        case .file(let reference):
            (URL(fileURLWithPath: reference.path), reference.isDirectory, reference.typeIdentifier)
        case .storedFile(let stored):
            (storage.url(for: stored), false, stored.typeIdentifier)
        case .pending, .link, .text:
            (nil, false, nil)
        }
    }

    private func retentionText(_ item: ShelfItem) -> String {
        guard let expiry = item.expiresAt else { return "Pinned" }
        let sameDay = calendar.isDate(expiry, inSameDayAs: now())
        return "Until " + expiry.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
    }

    // MARK: Expiry

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard schedulesExpiry, publisher != nil, let next = collection.nextExpiry else { return }
        let delay = max(next.timeIntervalSince(now()), 0)
        expiryTask = Task { [weak self] in
            // Continuous clock: keeps counting across sleep, so items leave on time after a wake.
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(1), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.expireItems()
        }
    }

    // MARK: Text

    static func kindDescription(isDirectory: Bool, typeIdentifier: String?) -> String {
        if isDirectory { return "Folder" }
        guard let type = typeIdentifier.flatMap(UTType.init) else { return "File" }
        if type.conforms(to: .pdf) { return "PDF" }
        if type.conforms(to: .image) { return "Image" }
        if type.conforms(to: .movie) { return "Movie" }
        if type.conforms(to: .audio) { return "Audio" }
        if type.conforms(to: .archive) { return "Archive" }
        if type.conforms(to: .application) || type.conforms(to: .applicationBundle) { return "App" }
        return type.localizedDescription ?? "File"
    }

    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    /// A name for data dropped without one, e.g. "Image 2026-10-08 at 14.05.12.png".
    static func fileName(for type: UTType, at date: Date) -> String {
        let kind = type.conforms(to: .pdf) ? "Document" : "Image"
        return "\(kind) \(fileNameDateFormatter.string(from: date)).\(type.preferredFilenameExtension ?? "data")"
    }

    static func summary(_ titles: [String]) -> String? {
        switch titles.count {
        case 0: nil
        case 1: titles[0]
        default: "\(titles.count) items"
        }
    }

    static func summary(of items: [NotchDrop.Item]) -> String? {
        let titles: [String] = items.map { item in
            switch item {
            case .file(let url): url.lastPathComponent
            case .filePromise: "File"
            case .contents(_, let type): type.conforms(to: .pdf) ? "PDF" : "Image"
            case .url(let url): ShelfText.linkTitle(url)
            case .text(let text): ShelfText.firstLine(of: text)
            }
        }
        return summary(titles)
    }
}
