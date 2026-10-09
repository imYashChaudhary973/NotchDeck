import Foundation
import Testing
import UniformTypeIdentifiers
@testable import NotchDeck

/// A pasteboard the test "copies" to.
@MainActor
final class FakeClipboardPasteboard: ClipboardPasteboard {
    var changeCount = 0
    var access: ClipboardAccess = .allowed
    var currentTypes: [String] = ["public.utf8-plain-text"]
    var current = ClipboardCapture.Snapshot()
    private(set) var snapshotReads = 0

    func types() -> [String] { currentTypes }

    func snapshot() -> ClipboardCapture.Snapshot {
        snapshotReads += 1
        return current
    }

    func copy(_ text: String, types: [String] = ["public.utf8-plain-text"]) {
        current = ClipboardCapture.Snapshot(string: text)
        currentTypes = types
        changeCount += 1
    }
}

@MainActor
final class FakeClipboardStore: ClipboardStoring {
    var history = ClipboardHistory()
    private(set) var images: [String: Data] = [:]
    private(set) var removedAll = false

    func load() -> ClipboardHistory { history }
    func save(_ history: ClipboardHistory) { self.history = history }

    func storeImage(_ data: Data, type: UTType, id: UUID) -> String? {
        let name = id.uuidString + ".png"
        images[name] = data
        return name
    }

    func imageURL(_ fileName: String) -> URL? { nil }
    func removeImage(_ fileName: String) { images[fileName] = nil }
    func removeOrphanedImages(keeping fileNames: Set<String>) { images = images.filter { fileNames.contains($0.key) } }

    func removeAll() {
        history = ClipboardHistory()
        images.removeAll()
        removedAll = true
    }
}

struct ClipboardHistoryTests {
    let start = Date(timeIntervalSinceReferenceDate: 50_000)
    let limits = ClipboardHistory.Limits(maxEntries: 3, retention: nil)

    private func entry(_ text: String, at offset: TimeInterval = 0, pinned: Bool = false) -> ClipboardEntry {
        let content = ClipboardContent.text(text, rtf: nil)
        return ClipboardEntry(
            content: content, kind: .text,
            fingerprint: ClipboardCapture.fingerprint(of: content),
            copiedAt: start.addingTimeInterval(offset), isPinned: pinned
        )
    }

    @Test func newestCopiesComeFirst() {
        var history = ClipboardHistory()
        _ = history.record(entry("a"), limits: limits, now: start)
        _ = history.record(entry("b", at: 1), limits: limits, now: start)

        #expect(history.entries.map(\.preview) == ["b", "a"])
    }

    @Test func copyingTheSameThingTwiceKeepsOneEntryAtTheTop() {
        var history = ClipboardHistory()
        let first = entry("same")
        _ = history.record(first, limits: limits, now: start)
        _ = history.record(entry("other", at: 1), limits: limits, now: start)
        history.setPinned(true, for: first.id)

        let unused = history.record(entry("same", at: 2), limits: limits, now: start)

        #expect(history.entries.map(\.preview) == ["same", "other"])
        #expect(history.entries[0].id == first.id)
        #expect(history.entries[0].isPinned)
        #expect(history.entries[0].copiedAt == start.addingTimeInterval(2))
        #expect(unused.isEmpty)
    }

    @Test func theOldestUnpinnedEntriesLeaveBeyondTheLimit() {
        var history = ClipboardHistory()
        let pinned = entry("pinned", pinned: true)
        _ = history.record(pinned, limits: limits, now: start)
        var removed: [ClipboardEntry] = []
        for index in 1...4 {
            removed += history.record(entry("item \(index)", at: TimeInterval(index)), limits: limits, now: start)
        }

        // Pinned entries don't count toward the limit.
        #expect(history.entries.map(\.preview) == ["item 4", "item 3", "item 2", "pinned"])
        #expect(removed.map(\.preview) == ["item 1"])
    }

    @Test func loweringTheLimitTrimsTheHistory() {
        var history = ClipboardHistory()
        for index in 1...3 {
            _ = history.record(entry("item \(index)", at: TimeInterval(index)), limits: limits, now: start)
        }

        let removed = history.enforce(ClipboardHistory.Limits(maxEntries: 1, retention: nil), now: start)

        #expect(history.entries.map(\.preview) == ["item 3"])
        #expect(removed.count == 2)
    }

    @Test func unpinnedEntriesAreForgottenAfterTheRetention() {
        var history = ClipboardHistory(entries: [entry("new", at: 3000), entry("old", at: 0), entry("pinned", at: -9000, pinned: true)])
        let retention = ClipboardHistory.Limits(maxEntries: 10, retention: 3600)

        #expect(history.nextRetentionExpiry(retention.retention) == start.addingTimeInterval(3600))
        let removed = history.enforce(retention, now: start.addingTimeInterval(3601))

        #expect(removed.map(\.preview) == ["old"])
        #expect(history.entries.map(\.preview) == ["new", "pinned"])
        #expect(history.nextRetentionExpiry(nil) == nil)
    }

    @Test func clearingKeepsPinnedEntriesUnlessAskedNotTo() {
        var history = ClipboardHistory(entries: [entry("a"), entry("b", pinned: true)])

        #expect(history.clear(includingPinned: false).map(\.preview) == ["a"])
        #expect(history.entries.map(\.preview) == ["b"])
        #expect(history.clear(includingPinned: true).map(\.preview) == ["b"])
        #expect(history.isEmpty)
    }

    @Test func searchMatchesEveryWordIgnoringCaseAndAccents() {
        var source = entry("Meeting notes for Café launch")
        source.sourceName = "Notes"
        let history = ClipboardHistory(entries: [source, entry("Unrelated")])

        #expect(history.search("cafe LAUNCH").count == 1)
        #expect(history.search("notes unrelated").isEmpty)
        #expect(history.search("  ").count == 2)
    }

    @Test func pinnedEntriesLeadTheNotch() {
        let history = ClipboardHistory(entries: [entry("a"), entry("b"), entry("pinned", pinned: true)])
        #expect(history.featured(limit: 2).map(\.preview) == ["pinned", "a"])
    }
}

struct ClipboardCaptureTests {
    @Test func concealedAndTransientContentIsNeverRead() {
        #expect(ClipboardCapture.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(ClipboardCapture.shouldIgnore(types: ["org.nspasteboard.TransientType"]))
        #expect(!ClipboardCapture.shouldIgnore(types: ["public.utf8-plain-text"]))
    }

    @Test func passwordManagersAndExcludedAppsAreSkipped() {
        #expect(ClipboardCapture.isExcluded("com.1password.1password", userExcluded: []))
        #expect(ClipboardCapture.isExcluded("com.example.secret", userExcluded: ["com.example.secret"]))
        #expect(!ClipboardCapture.isExcluded("com.apple.Safari", userExcluded: []))
        #expect(!ClipboardCapture.isExcluded(nil, userExcluded: []))
    }

    @Test func textIsClassified() {
        func kind(_ text: String, from bundleID: String? = nil) -> ClipboardKind? {
            if case .entry(_, let kind) = ClipboardCapture.result(from: .init(string: text), sourceBundleID: bundleID) { kind } else { nil }
        }
        #expect(kind("#FF8800") == .color)
        #expect(kind("rgb(255, 136, 0)") == .color)
        #expect(kind("https://apple.com/mac") == .link)
        #expect(kind("see https://apple.com") == .text)
        #expect(kind("Hello there") == .text)
        #expect(kind("anything", from: "com.apple.dt.Xcode") == .code)
        #expect(kind("   \n ") == nil)
        #expect(kind(String(repeating: "x", count: ClipboardCapture.maxTextLength + 1)) == nil)
    }

    @Test func filesComeBeforeTheirNames() {
        let snapshot = ClipboardCapture.Snapshot(fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")], string: "a.txt")
        #expect(ClipboardCapture.result(from: snapshot, sourceBundleID: nil) == .entry(.files([URL(fileURLWithPath: "/tmp/a.txt")]), .files))
    }

    @Test func largeRichTextKeepsOnlyItsPlainText() {
        let big = ClipboardCapture.Snapshot(string: "styled", rtf: Data(count: ClipboardCapture.maxRTFSize + 1))
        let small = ClipboardCapture.Snapshot(string: "styled", rtf: Data([1]))
        #expect(ClipboardCapture.result(from: big, sourceBundleID: nil) == .entry(.text("styled", rtf: nil), .text))
        #expect(ClipboardCapture.result(from: small, sourceBundleID: nil) == .entry(.text("styled", rtf: Data([1])), .text))
    }

    @Test func colorsRoundTripAsHex() {
        let color = ColorParser.parse("#f80")
        #expect(color == ColorComponents(red: 1, green: 0x88 / 255, blue: 0))
        #expect(color.map(ColorParser.hex) == "#FF8800")
        #expect(ColorParser.parse("#12345") == nil)
    }

    @Test func colorFingerprintsIgnoreCase() {
        let upper = ClipboardContent.color(ColorComponents(red: 1, green: 0, blue: 0), text: "#FF0000")
        let lower = ClipboardContent.color(ColorComponents(red: 1, green: 0, blue: 0), text: "#ff0000")
        #expect(ClipboardCapture.fingerprint(of: upper) == ClipboardCapture.fingerprint(of: lower))
    }
}

@MainActor
struct ClipboardProviderTests {
    let clock = TestClock()
    let pasteboard = FakeClipboardPasteboard()
    let writer = FakePasteboardWriter()
    let store = FakeClipboardStore()
    let workspace = FakeWorkspace()
    let engine: ActivityEngine
    let historyKey = ActivityKey(source: ActivitySource(rawValue: "clipboard"), id: ClipboardProvider.historyActivityID)
    let accessKey = ActivityKey(source: ActivitySource(rawValue: "clipboard"), id: ClipboardProvider.accessActivityID)

    final class Box {
        var configuration = ClipboardProvider.Configuration(limits: .init(maxEntries: 3, retention: nil))
        var frontmost: ClipboardSource? = ClipboardSource(bundleID: "com.apple.Notes", name: "Notes")
    }
    let box = Box()

    init() {
        let clock = clock
        engine = ActivityEngine(now: { clock.now }, schedulesExpiry: false)
    }

    private func makeProvider() -> ClipboardProvider {
        let clock = clock
        let box = box
        return ClipboardProvider(
            pasteboard: pasteboard,
            writer: writer,
            store: store,
            workspace: workspace,
            frontmostApplication: { box.frontmost },
            configuration: { box.configuration },
            now: { clock.now },
            schedulesWork: false
        )
    }

    private func copy(_ text: String, provider: ClipboardProvider) {
        pasteboard.copy(text)
        clock.advance(by: 1)
        provider.checkForChanges()
    }

    private var rows: CollectionContent? {
        if case .collection(let content) = engine.activity(for: historyKey)?.presentation.content { content } else { nil }
    }

    @Test func whatWasCopiedBeforeStartingIsNotRead() {
        pasteboard.copy("before")
        let provider = makeProvider()
        engine.register(provider)

        provider.checkForChanges()

        #expect(provider.history.isEmpty)
        #expect(pasteboard.snapshotReads == 0)
        #expect(engine.activity(for: historyKey) == nil)
    }

    @Test func copiesAreRecordedOnceAndListedInTheCommandCenter() {
        let provider = makeProvider()
        engine.register(provider)

        copy("first", provider: provider)
        copy("second", provider: provider)
        copy("first", provider: provider)
        provider.checkForChanges() // no change since

        #expect(provider.history.entries.map(\.preview) == ["first", "second"])
        #expect(provider.history.entries.first?.sourceName == "Notes")
        #expect(engine.activity(for: historyKey)?.placement == .commandCenter)
        #expect(rows?.layout == .rows)
        #expect(rows?.items.map(\.title) == ["first", "second"])
        #expect(store.history == provider.history)
    }

    @Test func theHistoryLimitIsApplied() {
        let provider = makeProvider()
        engine.register(provider)

        for index in 1...5 { copy("item \(index)", provider: provider) }

        #expect(provider.history.entries.map(\.preview) == ["item 5", "item 4", "item 3"])

        box.configuration.limits.maxEntries = 1
        provider.configurationChanged()
        #expect(provider.history.entries.map(\.preview) == ["item 5"])
    }

    @Test func pinnedEntriesSurviveLimitsAndClearing() throws {
        let provider = makeProvider()
        engine.register(provider)
        copy("keep", provider: provider)
        let id = try #require(provider.history.entries.first?.id)
        engine.perform(actionID: CollectionContent.actionID("pin", item: id.uuidString), on: historyKey)

        for index in 1...5 { copy("item \(index)", provider: provider) }
        #expect(provider.history.entry(id) != nil)

        engine.perform(actionID: ClipboardProvider.ActionID.clear, on: historyKey)
        #expect(provider.history.entries.map(\.id) == [id])
    }

    @Test func concealedCopiesAndExcludedAppsAreNeverRead() {
        let provider = makeProvider()
        engine.register(provider)

        pasteboard.copy("hunter2", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
        provider.checkForChanges()
        box.frontmost = ClipboardSource(bundleID: "com.bitwarden.desktop", name: "Bitwarden")
        copy("p4ssw0rd", provider: provider)
        box.configuration.excludedBundleIDs = ["com.example.secret"]
        box.frontmost = ClipboardSource(bundleID: "com.example.secret", name: "Secret")
        copy("secret", provider: provider)

        #expect(provider.history.isEmpty)
        #expect(pasteboard.snapshotReads == 0)
    }

    @Test func pausingStopsRecordingAndShowsPaused() {
        let provider = makeProvider()
        engine.register(provider)
        box.configuration.isPaused = true
        provider.configurationChanged()

        copy("while paused", provider: provider)

        #expect(provider.history.isEmpty)
        #expect(engine.activity(for: historyKey)?.subtitle == "Paused")
        #expect(engine.activity(for: historyKey)?.actions.contains { $0.id == ClipboardProvider.ActionID.resume } == true)
    }

    @Test func copyingFromTheHistoryIsNotRecordedAgain() throws {
        let provider = makeProvider()
        engine.register(provider)
        copy("a", provider: provider)
        copy("b", provider: provider)
        let a = try #require(provider.history.entries.last?.id)

        engine.perform(actionID: CollectionContent.actionID("copy", item: a.uuidString), on: historyKey)
        pasteboard.changeCount = writer.changeCount
        provider.checkForChanges()

        #expect(writer.written == [.text("a", rtf: nil)])
        #expect(provider.history.entries.map(\.preview) == ["a", "b"])
        #expect(pasteboard.snapshotReads == 2)
    }

    @Test func deletingRemovesAnEntry() throws {
        let provider = makeProvider()
        engine.register(provider)
        copy("gone", provider: provider)
        let id = try #require(provider.history.entries.first?.id)

        engine.perform(actionID: CollectionContent.actionID("delete", item: id.uuidString), on: historyKey)

        #expect(provider.history.isEmpty)
        #expect(engine.activity(for: historyKey) == nil)
    }

    @Test func historyIsRestoredAfterARelaunch() {
        let first = makeProvider()
        engine.register(first)
        copy("remember me", provider: first)
        engine.unregister(first.source)

        let second = makeProvider()
        engine.register(second)

        #expect(second.history.entries.map(\.preview) == ["remember me"])
    }

    @Test func clearingEverythingWorksWhileOff() {
        let provider = makeProvider()
        engine.register(provider)
        copy("a", provider: provider)
        engine.unregister(provider.source)

        provider.clearHistory(includingPinned: true)

        #expect(provider.history.isEmpty)
        #expect(store.removedAll)
    }

    @Test func deniedAccessIsExplainedInsteadOfReading() {
        pasteboard.access = .denied
        let provider = makeProvider()
        engine.register(provider)

        copy("anything", provider: provider)

        #expect(provider.history.isEmpty)
        #expect(pasteboard.snapshotReads == 0)
        #expect(engine.activity(for: accessKey)?.title == "Clipboard access is off")
        engine.perform(actionID: ClipboardProvider.ActionID.openSettings, on: accessKey)
        #expect(workspace.opened == [ClipboardProvider.privacySettingsURL])
    }
}
