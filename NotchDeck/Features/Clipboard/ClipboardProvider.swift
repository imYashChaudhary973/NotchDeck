import AppKit
import Observation
import UniformTypeIdentifiers

/// Clipboard history: what the user copies, kept on this Mac so it can be copied again.
///
/// Off by default. macOS has no notification for clipboard changes, so while the feature is on,
/// not paused and the screens are awake, the provider reads the pasteboard's change count once a
/// second. That counter never reveals contents. Contents are read only after a change, and never
/// for concealed or transient content, password managers or excluded apps. Nothing is logged or
/// sent anywhere.
///
/// The command center lists the most recent entries; the History window searches all of them.
@MainActor
@Observable
final class ClipboardProvider: ActivityProvider {
    struct Configuration: Equatable, Sendable {
        var limits = ClipboardHistory.Limits(maxEntries: 50, retention: 7 * 86_400)
        /// Apps whose copies aren't kept, besides the password managers that never are.
        var excludedBundleIDs: Set<String> = []
        var isPaused = false
    }

    let source = ActivitySource(rawValue: "clipboard")
    static let historyActivityID = "history"
    static let accessActivityID = "access"
    /// Below the calendar schedule (17), above Volume (14) and the metric rows.
    static let priority = ActivityPriority(rawValue: 16)
    static let pollInterval: Duration = .seconds(1)
    /// Entries listed in the notch; the History window shows all of them.
    static let notchEntryLimit = 5
    /// Saving waits briefly so a burst of copies writes the history file once.
    static let saveDelay: Duration = .seconds(1)
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!

    enum ItemAction: String {
        case copy, pin, unpin, delete
    }

    enum ActionID {
        static let showHistory = "showHistory"
        static let pause = "pause"
        static let resume = "resume"
        static let clear = "clear"
        static let openSettings = "openSettings"
    }

    /// Observed by the History window.
    private(set) var history = ClipboardHistory()
    private(set) var access: ClipboardAccess = .allowed
    /// Image thumbnails by entry, made when an image is copied or first shown.
    private(set) var thumbnails: [UUID: Data] = [:]

    /// Opens the History window (search).
    @ObservationIgnored var onShowHistory: (() -> Void)?
    /// Pauses or resumes keeping copies (a setting).
    @ObservationIgnored var onSetPaused: ((Bool) -> Void)?

    @ObservationIgnored private var publisher: ActivityPublisher?
    @ObservationIgnored private var lastChangeCount: Int?
    /// The change count of NotchDeck's own last write, so copying from the history isn't recorded again.
    @ObservationIgnored private var ownChangeCount: Int?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var retentionTask: Task<Void, Never>?
    /// The latest image capture, so tests can wait for it.
    @ObservationIgnored private(set) var imageCaptureTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailAttempts: Set<UUID> = []
    @ObservationIgnored private var sessionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var isSessionActive = true
    @ObservationIgnored private var isDisplayed = false

    @ObservationIgnored private let pasteboard: any ClipboardPasteboard
    @ObservationIgnored private let writer: any PasteboardWriting
    @ObservationIgnored private let store: any ClipboardStoring
    @ObservationIgnored private let workspace: any WorkspaceOpening
    @ObservationIgnored private let frontmostApplication: @MainActor () -> ClipboardSource?
    @ObservationIgnored private let configuration: () -> Configuration
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let schedulesWork: Bool

    /// - Parameters:
    ///   - frontmostApplication: The app a copy is attributed to.
    ///   - schedulesWork: When `false`, nothing polls or waits: tests call `checkForChanges()` and saves happen at once.
    init(
        pasteboard: any ClipboardPasteboard = SystemClipboardPasteboard(),
        writer: any PasteboardWriting = SystemPasteboardWriter(),
        store: any ClipboardStoring = ClipboardDirectoryStore(),
        workspace: any WorkspaceOpening = SystemWorkspace(),
        frontmostApplication: @escaping @MainActor () -> ClipboardSource? = ClipboardProvider.systemFrontmostApplication,
        configuration: @escaping () -> Configuration = { Configuration() },
        now: @escaping () -> Date = { .now },
        schedulesWork: Bool = true
    ) {
        self.pasteboard = pasteboard
        self.writer = writer
        self.store = store
        self.workspace = workspace
        self.frontmostApplication = frontmostApplication
        self.configuration = configuration
        self.now = now
        self.schedulesWork = schedulesWork
    }

    static func systemFrontmostApplication() -> ClipboardSource? {
        NSWorkspace.shared.frontmostApplication.map {
            ClipboardSource(bundleID: $0.bundleIdentifier, name: $0.localizedName)
        }
    }

    var isRunning: Bool { publisher != nil }

    // MARK: ActivityProvider

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
        history = store.load()
        cleanUp(history.enforce(configuration().limits, now: now()))
        store.removeOrphanedImages(keeping: imageFileNames)
        access = pasteboard.access
        // What is on the clipboard now was copied before NotchDeck was watching. Reading it at launch
        // would surprise the user (and could show the privacy prompt), so start from here.
        lastChangeCount = pasteboard.changeCount
        observeSession()
        publish()
        updatePolling()
        scheduleRetention()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        retentionTask?.cancel()
        retentionTask = nil
        if saveTask != nil {
            saveTask?.cancel()
            saveTask = nil
            store.save(history)
        }
        sessionObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        sessionObservers.removeAll()
        publisher = nil
        isDisplayed = false
    }

    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
        switch actionID {
        case ActionID.showHistory: onShowHistory?()
        case ActionID.pause: onSetPaused?(true)
        case ActionID.resume: onSetPaused?(false)
        case ActionID.clear: clearHistory(includingPinned: false)
        case ActionID.openSettings: workspace.open(Self.privacySettingsURL)
        default:
            guard let (name, itemID) = CollectionContent.itemAction(from: actionID),
                  let action = ItemAction(rawValue: name),
                  let id = UUID(uuidString: itemID) else { return }
            switch action {
            case .copy: copy(id)
            case .pin: setPinned(true, for: id)
            case .unpin: setPinned(false, for: id)
            case .delete: delete(id)
            }
        }
    }

    func displayedActivitiesChanged(_ ids: Set<NotchActivity.ID>) {
        let displayed = ids.contains(Self.historyActivityID)
        let appeared = displayed && !isDisplayed
        isDisplayed = displayed
        guard appeared else { return }
        // Catch up right away rather than at the next check, and refresh the entries' ages.
        checkForChanges()
        publish()
        loadThumbnails(for: history.featured(limit: Self.notchEntryLimit))
    }

    // MARK: Watching the clipboard

    /// Records the clipboard if it changed since the last check. Called once a second while watching.
    func checkForChanges() {
        guard isRunning else { return }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard count != ownChangeCount, !configuration().isPaused else { return }
        updateAccess()
        guard access == .allowed else { return }
        capture()
    }

    /// Reads the clipboard once, right after the user turned the feature on. If macOS hasn't asked
    /// about clipboard access yet, it asks now, in context, and NotchDeck then appears in
    /// Privacy & Security ▸ Paste from Other Apps.
    func captureCurrentClipboard() {
        guard isRunning, !configuration().isPaused else { return }
        updateAccess()
        guard access == .allowed else { return }
        lastChangeCount = pasteboard.changeCount
        capture()
        updateAccess()
    }

    /// Re-reads the privacy setting (it can change in System Settings at any time).
    func updateAccess() {
        let current = pasteboard.access
        guard current != access else { return }
        access = current
        publish()
    }

    private func capture() {
        let types = pasteboard.types()
        guard !types.isEmpty, !ClipboardCapture.shouldIgnore(types: types) else { return }
        let source = frontmostApplication()
        guard !ClipboardCapture.isExcluded(source?.bundleID, userExcluded: configuration().excludedBundleIDs) else { return }
        guard let result = ClipboardCapture.result(from: pasteboard.snapshot(), sourceBundleID: source?.bundleID) else { return }

        let date = now()
        switch result {
        case .entry(let content, let kind):
            record(ClipboardEntry(
                content: content,
                kind: kind,
                fingerprint: ClipboardCapture.fingerprint(of: content),
                copiedAt: date,
                source: source
            ))
        case .image(let data, let type):
            captureImage(data, type: type, at: date, source: source)
        }
    }

    /// Hashing, measuring and thumbnailing run off the main thread; the image is stored only if it
    /// isn't in the history already.
    private func captureImage(_ data: Data, type: UTType, at date: Date, source: ClipboardSource?) {
        let preparing = Task.detached(priority: .utility) { ClipboardImageProcessing.prepare(data) }
        imageCaptureTask = Task { [weak self] in
            guard let prepared = await preparing.value, let self, self.isRunning else { return }
            if self.history.moveToTop(fingerprint: prepared.fingerprint, at: date, source: source) {
                self.changed()
                return
            }
            let id = UUID()
            guard let fileName = self.store.storeImage(data, type: type, id: id) else { return }
            if let thumbnail = prepared.thumbnail {
                self.thumbnails[id] = thumbnail
            }
            self.thumbnailAttempts.insert(id)
            self.record(ClipboardEntry(
                id: id,
                content: .image(ClipboardImage(
                    fileName: fileName,
                    typeIdentifier: type.identifier,
                    pixelWidth: prepared.pixelWidth,
                    pixelHeight: prepared.pixelHeight
                )),
                kind: .image,
                fingerprint: prepared.fingerprint,
                copiedAt: date,
                source: source
            ))
        }
    }

    private func record(_ entry: ClipboardEntry) {
        cleanUp(history.record(entry, limits: configuration().limits, now: now()))
        changed()
    }

    // MARK: Commands

    /// Puts an entry back on the clipboard and moves it to the top.
    func copy(_ id: UUID) {
        guard let entry = history.entry(id), let payload = payload(for: entry) else { return }
        let count = writer.write(payload)
        ownChangeCount = count
        lastChangeCount = count
        history.moveToTop(fingerprint: entry.fingerprint, at: now())
        changed()
    }

    func setPinned(_ isPinned: Bool, for id: UUID) {
        guard history.setPinned(isPinned, for: id) else { return }
        // Unpinning may put the history over its limits.
        if !isPinned { cleanUp(history.enforce(configuration().limits, now: now())) }
        changed()
    }

    func delete(_ id: UUID) {
        guard let removed = history.remove(id) else { return }
        cleanUp([removed])
        changed()
    }

    /// Clears unpinned entries, or everything. Clearing everything also works while the feature is
    /// off, deleting what was stored.
    func clearHistory(includingPinned: Bool) {
        guard isRunning else {
            if includingPinned {
                history = ClipboardHistory()
                thumbnails.removeAll()
                store.removeAll()
            }
            return
        }
        cleanUp(history.clear(includingPinned: includingPinned))
        if includingPinned { store.removeAll() }
        changed()
    }

    func search(_ query: String) -> [ClipboardEntry] {
        history.search(query)
    }

    /// Applies changed settings: limits, exclusions, pause.
    func configurationChanged() {
        guard isRunning else { return }
        cleanUp(history.enforce(configuration().limits, now: now()))
        changed()
        updatePolling()
    }

    /// Makes thumbnails for image entries that don't have one yet (after a relaunch).
    func loadThumbnails(for entries: [ClipboardEntry]) {
        for entry in entries {
            guard case .image(let image) = entry.content,
                  thumbnails[entry.id] == nil,
                  !thumbnailAttempts.contains(entry.id),
                  let url = store.imageURL(image.fileName) else { continue }
            thumbnailAttempts.insert(entry.id)
            let id = entry.id
            Task { [weak self] in
                let data = await Task.detached(priority: .utility) { ClipboardImageProcessing.thumbnail(at: url) }.value
                guard let self, let data, self.history.entry(id) != nil else { return }
                self.thumbnails[id] = data
                self.publish()
            }
        }
    }

    // MARK: Helpers

    private var imageFileNames: Set<String> {
        Set(history.entries.compactMap { entry in
            if case .image(let image) = entry.content { image.fileName } else { nil }
        })
    }

    /// Deletes what removed entries stored.
    private func cleanUp(_ removed: [ClipboardEntry]) {
        let kept = imageFileNames
        for entry in removed {
            thumbnails[entry.id] = nil
            thumbnailAttempts.remove(entry.id)
            if case .image(let image) = entry.content, !kept.contains(image.fileName) {
                store.removeImage(image.fileName)
            }
        }
    }

    private func payload(for entry: ClipboardEntry) -> PasteboardPayload? {
        switch entry.content {
        case .text(let text, let rtf):
            return .text(text, rtf: rtf)
        case .link(let url):
            return .url(url)
        case .color(let color, let text):
            return .color(color, text: text)
        case .image(let image):
            guard let url = store.imageURL(image.fileName), let data = try? Data(contentsOf: url) else { return nil }
            return .data(data, UTType(image.typeIdentifier) ?? .png)
        case .files(let urls):
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            return existing.isEmpty ? nil : .files(existing)
        }
    }

    // MARK: Scheduling

    private func changed() {
        scheduleSave()
        publish()
        scheduleRetention()
    }

    private func scheduleSave() {
        guard schedulesWork else {
            store.save(history)
            return
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            self.store.save(self.history)
        }
    }

    /// Checks the change count once a second, only while running, not paused and the screens are awake.
    private func updatePolling() {
        let shouldPoll = schedulesWork && isRunning && isSessionActive && !configuration().isPaused
        guard shouldPoll != (pollTask != nil) else { return }
        if shouldPoll {
            // Copies made while paused or asleep aren't recorded.
            lastChangeCount = pasteboard.changeCount
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pollInterval, tolerance: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    self?.checkForChanges()
                }
            }
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    /// Wakes once, when the oldest unpinned entry passes the retention.
    private func scheduleRetention() {
        retentionTask?.cancel()
        retentionTask = nil
        guard schedulesWork, isRunning, let next = history.nextRetentionExpiry(configuration().limits.retention) else { return }
        let delay = max(next.timeIntervalSince(now()), 0) + 1
        retentionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(60), clock: .continuous)
            guard !Task.isCancelled, let self else { return }
            self.cleanUp(self.history.enforce(self.configuration().limits, now: self.now()))
            self.changed()
        }
    }

    /// Stops checking while the screens sleep or another user is active.
    private func observeSession() {
        guard schedulesWork, sessionObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let pauses = [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
        let resumes = [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
        for name in pauses + resumes {
            let isActive = resumes.contains(name)
            sessionObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isSessionActive = isActive
                    self?.updatePolling()
                }
            })
        }
    }

    // MARK: Publishing

    private func publish() {
        guard let publisher else { return }
        if let activity = accessActivity() {
            publisher.publish(activity)
        } else {
            publisher.withdraw(id: Self.accessActivityID)
        }
        if let activity = historyActivity() {
            publisher.publish(activity)
        } else {
            publisher.withdraw(id: Self.historyActivityID)
        }
    }

    private func accessActivity() -> NotchActivity? {
        let title: String
        switch access {
        case .allowed: return nil
        case .askEachTime: title = "Clipboard history needs access"
        case .denied: title = "Clipboard access is off"
        }
        return NotchActivity(
            id: Self.accessActivityID,
            source: source,
            kind: .clipboard,
            priority: Self.priority,
            placement: .commandCenter,
            title: title,
            subtitle: "Allow NotchDeck in Paste from Other Apps",
            presentation: ActivityPresentation(symbolName: "lock.doc", accent: .green),
            actions: [ActivityAction(id: ActionID.openSettings, title: "Open Settings…")]
        )
    }

    /// The most recent entries, while there are any or the history is paused.
    private func historyActivity() -> NotchActivity? {
        let isPaused = configuration().isPaused
        guard !history.isEmpty || isPaused else { return nil }
        let shown = history.featured(limit: Self.notchEntryLimit)
        let date = now()
        let count = history.entries.count
        return NotchActivity(
            id: Self.historyActivityID,
            source: source,
            kind: .clipboard,
            priority: Self.priority,
            placement: .commandCenter,
            title: "Clipboard",
            subtitle: isPaused ? "Paused" : (count == 1 ? "1 item" : "\(count) items"),
            presentation: ActivityPresentation(
                symbolName: isPaused ? "pause.circle.fill" : "doc.on.clipboard.fill",
                accent: .green,
                content: .collection(CollectionContent(
                    layout: .rows,
                    items: shown.map { collectionItem($0, at: date) },
                    emptyText: "Paused. New copies aren't kept.",
                    hiddenCount: count - shown.count
                ))
            ),
            actions: [
                ActivityAction(id: ActionID.showHistory, title: "Search History", systemImage: "magnifyingglass"),
                isPaused
                    ? ActivityAction(id: ActionID.resume, title: "Resume", systemImage: "play.fill")
                    : ActivityAction(id: ActionID.pause, title: "Pause", systemImage: "pause.fill"),
                ActivityAction(id: ActionID.clear, title: "Clear Unpinned", systemImage: "trash", isDestructive: true),
            ]
        )
    }

    private func collectionItem(_ entry: ClipboardEntry, at date: Date) -> CollectionContent.Item {
        let itemID = entry.id.uuidString
        func action(_ action: ItemAction, _ title: String, _ image: String, destructive: Bool = false) -> ActivityAction {
            ActivityAction(id: CollectionContent.actionID(action.rawValue, item: itemID), title: title, systemImage: image, isDestructive: destructive)
        }
        let copy = action(.copy, "Copy", "doc.on.doc")
        let payload: CollectionContent.Payload? = switch entry.content {
        case .text(let text, _): .text(text)
        case .link(let url): .url(url)
        case .color(_, let text): .text(text)
        case .image(let image): store.imageURL(image.fileName).map(CollectionContent.Payload.file)
        case .files(let urls): urls.first.map(CollectionContent.Payload.file)
        }
        var color: ColorComponents?
        if case .color(let components, _) = entry.content { color = components }

        return CollectionContent.Item(
            id: itemID,
            title: entry.preview,
            subtitle: ClipboardText.age(of: entry.copiedAt, at: date),
            symbolName: entry.kind.symbolName,
            thumbnail: thumbnails[entry.id],
            color: color,
            isPinned: entry.isPinned,
            isMonospaced: entry.kind == .code,
            payload: payload,
            primaryActionID: copy.id,
            menuActions: [
                copy,
                entry.isPinned ? action(.unpin, "Unpin", "pin.slash") : action(.pin, "Pin", "pin"),
                action(.delete, "Delete", "trash", destructive: true),
            ]
        )
    }
}
