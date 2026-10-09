import Foundation
import Testing
import UniformTypeIdentifiers
@testable import NotchDeck

/// In-memory shelf storage. Files listed in `missingPaths` resolve as missing.
@MainActor
final class FakeShelfStorage: ShelfStoring {
    var savedItems: [ShelfItem] = []
    var missingPaths: Set<String> = []
    private(set) var storedIDs: Set<UUID> = []
    private(set) var removedFileIDs: [UUID] = []

    func loadItems() -> [ShelfItem] { savedItems }
    func saveItems(_ items: [ShelfItem]) { savedItems = items.filter { !$0.isPending } }

    func makeReference(to url: URL) -> ShelfFileReference? {
        guard !missingPaths.contains(url.path) else { return nil }
        return ShelfFileReference(bookmark: Data(), path: url.path, name: url.lastPathComponent, isDirectory: false, typeIdentifier: UTType.pdf.identifier)
    }

    func resolve(_ reference: ShelfFileReference) -> ShelfFileResolution {
        missingPaths.contains(reference.path) ? .missing : .available(URL(fileURLWithPath: reference.path), updated: nil)
    }

    func store(_ data: Data, name: String, for id: UUID) -> ShelfStoredFile? {
        storedIDs.insert(id)
        return ShelfStoredFile(relativePath: "\(id.uuidString)/\(name)", name: name, typeIdentifier: UTType.png.identifier)
    }

    func promiseDirectory(for id: UUID) -> URL? { nil }
    func adopt(_ url: URL, for id: UUID) -> ShelfStoredFile? { nil }
    func url(for stored: ShelfStoredFile) -> URL? { URL(fileURLWithPath: "/tmp/shelf/" + stored.relativePath) }

    func removeFiles(for id: UUID) {
        storedIDs.remove(id)
        removedFileIDs.append(id)
    }

    func removeOrphanedFiles(keeping ids: Set<UUID>) {
        storedIDs.formIntersection(ids)
    }
}

@MainActor
final class FakeShelfSystem: ShelfSystemActions {
    private(set) var revealed: [[URL]] = []
    private(set) var opened: [URL] = []
    private(set) var previewed: [[URL]] = []
    private(set) var airDropped: [[ShelfShareItem]] = []

    func reveal(_ urls: [URL]) { revealed.append(urls) }
    func open(_ url: URL) { opened.append(url) }
    func quickLook(_ urls: [URL]) { previewed.append(urls) }
    func airDrop(_ items: [ShelfShareItem]) -> Bool {
        airDropped.append(items)
        return true
    }
}

@MainActor
struct FakeThumbnailer: ThumbnailGenerating {
    func thumbnail(for url: URL) async -> Data? { nil }
}

@MainActor
final class FakePasteboardWriter: PasteboardWriting {
    private(set) var written: [PasteboardPayload] = []
    private(set) var changeCount = 0

    func write(_ payload: PasteboardPayload) -> Int {
        written.append(payload)
        changeCount += 1
        return changeCount
    }
}

struct ShelfCollectionTests {
    let date = Date(timeIntervalSinceReferenceDate: 10_000)

    private func item(_ text: String, retention: ShelfRetention? = nil) -> ShelfItem {
        ShelfItem(content: .text(text), addedAt: date, retention: retention ?? .until(date.addingTimeInterval(3600)))
    }

    @Test func addsNewItemsInFrontInDropOrder() {
        var collection = ShelfCollection(items: [item("old")])

        let result = collection.add([item("a"), item("b")])

        #expect(collection.items.map(\.content.title) == ["a", "b", "old"])
        #expect(result.added.map(\.content.title) == ["a", "b"])
        #expect(result.removed.isEmpty)
    }

    @Test func droppingTheSameThingAgainMovesItToTheFrontKeepingItsPin() {
        let pinned = item("same", retention: .pinned)
        var collection = ShelfCollection(items: [item("other"), pinned])

        let result = collection.add([item("same")])

        #expect(collection.items.count == 2)
        #expect(collection.items.first?.id == pinned.id)
        #expect(collection.items.first?.isPinned == true)
        #expect(result.added.map(\.id) == [pinned.id])
    }

    @Test func droppingAgainExtendsButNeverShortensRetention() {
        let existing = item("x", retention: .until(date.addingTimeInterval(7200)))
        var collection = ShelfCollection(items: [existing])

        _ = collection.add([item("x", retention: .until(date.addingTimeInterval(60)))])
        #expect(collection.items.first?.expiresAt == date.addingTimeInterval(7200))

        _ = collection.add([item("x", retention: .until(date.addingTimeInterval(10_000)))])
        #expect(collection.items.first?.expiresAt == date.addingTimeInterval(10_000))
    }

    @Test func beyondTheLimitTheOldestUnpinnedItemsMakeRoom() {
        let pinnedOldest = item("pinned", retention: .pinned)
        let unpinned = (0..<ShelfCollection.maxItems - 1).map { item("item \($0)") }
        var collection = ShelfCollection(items: unpinned + [pinnedOldest])

        let result = collection.add([item("new")])

        #expect(collection.items.count == ShelfCollection.maxItems)
        #expect(collection.items.first?.content.title == "new")
        #expect(collection.items.contains { $0.id == pinnedOldest.id })
        #expect(result.removed.map(\.content.title) == ["item \(ShelfCollection.maxItems - 2)"])
    }

    @Test func expiredItemsAreRemovedAndPinnedOnesStay() {
        let soon = item("soon", retention: .until(date.addingTimeInterval(60)))
        let later = item("later", retention: .until(date.addingTimeInterval(600)))
        let pinned = item("pinned", retention: .pinned)
        var collection = ShelfCollection(items: [soon, later, pinned])

        #expect(collection.nextExpiry == date.addingTimeInterval(60))
        #expect(collection.removeExpired(at: date.addingTimeInterval(59)).isEmpty)

        let removed = collection.removeExpired(at: date.addingTimeInterval(60))

        #expect(removed.map(\.id) == [soon.id])
        #expect(collection.items.map(\.id) == [later.id, pinned.id])
        #expect(collection.nextExpiry == date.addingTimeInterval(600))
    }

    @Test func clearingRemovesOnlyUnpinnedItems() {
        let pinned = item("pinned", retention: .pinned)
        var collection = ShelfCollection(items: [item("a"), pinned, item("b")])

        let removed = collection.removeUnpinned()

        #expect(removed.count == 2)
        #expect(collection.items.map(\.id) == [pinned.id])
        #expect(collection.nextExpiry == nil)
    }

    @Test func pinnedOutlastsAnyDate() {
        #expect(ShelfRetention.longer(.pinned, .until(date)) == .pinned)
        #expect(ShelfRetention.longer(.until(date), .pinned) == .pinned)
        #expect(ShelfRetention.longer(.until(date), .until(date.addingTimeInterval(1))) == .until(date.addingTimeInterval(1)))
    }

    @Test func lifetimesEndAfterAnHourOrAtMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 14, minute: 30))!

        #expect(ShelfLifetime.oneHour.expiry(from: afternoon, calendar: calendar) == afternoon.addingTimeInterval(3600))
        #expect(ShelfLifetime.endOfDay.expiry(from: afternoon, calendar: calendar)
            == calendar.date(from: DateComponents(year: 2026, month: 10, day: 9)))
    }

    @Test func onlyFilesLinksAndTextAreDeduplicated() {
        let stored = ShelfItemContent.storedFile(ShelfStoredFile(relativePath: "a/b.png", name: "b.png"))
        #expect(stored.duplicateKey == nil)
        #expect(ShelfItemContent.pending(name: "x").duplicateKey == nil)
        #expect(ShelfItemContent.link(URL(string: "https://apple.com")!).duplicateKey != nil)
        #expect(stored.ownsFiles)
        #expect(!ShelfItemContent.text("t").ownsFiles)
    }

    @Test func linkTitlesDropWWWAndSlashes() {
        #expect(ShelfText.linkTitle(URL(string: "https://www.apple.com/mac/")!) == "apple.com/mac")
        #expect(ShelfText.linkTitle(URL(string: "https://apple.com")!) == "apple.com")
    }
}

@MainActor
struct ShelfProviderTests {
    let clock = TestClock()
    let storage = FakeShelfStorage()
    let system = FakeShelfSystem()
    let pasteboard = FakePasteboardWriter()
    let engine: ActivityEngine
    let itemsKey = ActivityKey(source: ActivitySource(rawValue: "shelf"), id: ShelfProvider.itemsActivityID)
    let confirmationKey = ActivityKey(source: ActivitySource(rawValue: "shelf"), id: ShelfProvider.confirmationActivityID)

    init() {
        let clock = clock
        engine = ActivityEngine(now: { clock.now }, schedulesExpiry: false)
    }

    private func makeProvider(lifetime: ShelfLifetime = .oneHour) -> ShelfProvider {
        let clock = clock
        return ShelfProvider(
            storage: storage,
            thumbnailer: FakeThumbnailer(),
            system: system,
            pasteboard: pasteboard,
            lifetime: { lifetime },
            now: { clock.now },
            schedulesExpiry: false
        )
    }

    private var collection: CollectionContent? {
        if case .collection(let content) = engine.activity(for: itemsKey)?.presentation.content { content } else { nil }
    }

    @discardableResult
    private func drop(_ items: [NotchDrop.Item], on target: NotchDrop.Target = .shelf) -> Bool {
        engine.routeDrop(NotchDrop(items: items, target: target))
    }

    private func perform(_ action: ShelfProvider.ItemAction, on id: UUID) {
        engine.perform(actionID: CollectionContent.actionID(action.rawValue, item: id.uuidString), on: itemsKey)
    }

    @Test func emptyShelfPublishesNothingButAcceptsDrops() {
        engine.register(makeProvider())

        #expect(engine.acceptsDrops)
        #expect(engine.activity(for: itemsKey) == nil)
    }

    @Test func droppedTextAndLinksBecomeItemsAndAreConfirmed() {
        let provider = makeProvider()
        engine.register(provider)

        #expect(drop([.url(URL(string: "https://apple.com/mac")!), .text("Hello\nworld")]))

        #expect(provider.collection.items.map(\.content.title) == ["apple.com/mac", "Hello"])
        #expect(collection?.layout == .tiles)
        #expect(collection?.items.first?.payload == .url(URL(string: "https://apple.com/mac")!))
        #expect(engine.activity(for: itemsKey)?.placement == .commandCenter)
        #expect(engine.activity(for: confirmationKey)?.title == "Added to Shelf")
        #expect(storage.savedItems.count == 2)
    }

    @Test func droppedFilesAreReferencedNotCopied() {
        let provider = makeProvider()
        engine.register(provider)

        #expect(drop([.file(URL(fileURLWithPath: "/Users/me/Report.pdf"))]))

        guard case .file(let reference) = provider.collection.items.first?.content else {
            Issue.record("Expected a file reference")
            return
        }
        #expect(reference.path == "/Users/me/Report.pdf")
        #expect(storage.storedIDs.isEmpty)
        #expect(collection?.items.first?.payload == .file(URL(fileURLWithPath: "/Users/me/Report.pdf")))
    }

    @Test func unusableDropsAreRejected() {
        let provider = makeProvider()
        engine.register(provider)

        #expect(!drop([.url(URL(string: "javascript:alert(1)")!), .text("   \n")]))
        #expect(!drop([]))
        #expect(provider.collection.isEmpty)
        #expect(engine.activity(for: confirmationKey) == nil)
    }

    @Test func itemsExpireAfterTheirLifetime() {
        let provider = makeProvider()
        engine.register(provider)
        drop([.text("note")])

        clock.advance(by: 3599)
        provider.expireItems()
        #expect(provider.collection.items.count == 1)

        clock.advance(by: 1)
        provider.expireItems()
        #expect(provider.collection.isEmpty)
        #expect(engine.activity(for: itemsKey) == nil)
        #expect(storage.savedItems.isEmpty)
    }

    @Test func pinnedItemsNeverExpireAndUnpinningRestartsTheLifetime() throws {
        let provider = makeProvider()
        engine.register(provider)
        drop([.text("keep me")])
        let id = try #require(provider.collection.items.first?.id)

        perform(.pin, on: id)
        #expect(provider.collection.item(id)?.isPinned == true)
        #expect(collection?.items.first?.isPinned == true)

        clock.advance(by: 86_400 * 3)
        provider.expireItems()
        #expect(provider.collection.item(id) != nil)

        perform(.unpin, on: id)
        #expect(provider.collection.item(id)?.expiresAt == clock.now.addingTimeInterval(3600))
    }

    @Test func keepUntilTonightExtendsAnItem() throws {
        let provider = makeProvider()
        engine.register(provider)
        drop([.text("today")])
        let id = try #require(provider.collection.items.first?.id)

        perform(.keepToday, on: id)

        let expiry = try #require(provider.collection.item(id)?.expiresAt)
        #expect(expiry == ShelfLifetime.endOfDay.expiry(from: clock.now))
    }

    @Test func clearingKeepsPinnedItems() throws {
        let provider = makeProvider()
        engine.register(provider)
        drop([.text("a"), .text("b")])
        let pinned = try #require(provider.collection.items.last?.id)
        perform(.pin, on: pinned)

        engine.perform(actionID: ShelfProvider.ActionID.clear, on: itemsKey)

        #expect(provider.collection.items.map(\.id) == [pinned])
        // Nothing left to clear.
        #expect(engine.activity(for: itemsKey)?.actions.isEmpty == true)
    }

    @Test func removingAnItemDeletesWhatTheShelfStoredForIt() throws {
        let provider = makeProvider()
        engine.register(provider)
        drop([.contents(Data([1, 2, 3]), .png)])
        let id = try #require(provider.collection.items.first?.id)
        #expect(storage.storedIDs == [id])

        perform(.remove, on: id)

        #expect(provider.collection.isEmpty)
        #expect(storage.removedFileIDs == [id])
        #expect(storage.storedIDs.isEmpty)
    }

    @Test func itemsSurviveARelaunchAndExpiredOnesAreDropped() {
        let first = makeProvider()
        engine.register(first)
        drop([.text("short")])
        clock.advance(by: 1800)
        drop([.text("longer")])
        engine.unregister(first.source)

        clock.advance(by: 1800)
        let second = makeProvider()
        engine.register(second)

        #expect(second.collection.items.map(\.content.title) == ["longer"])
    }

    @Test func missingFilesAreShownUnavailable() {
        let provider = makeProvider()
        engine.register(provider)
        drop([.file(URL(fileURLWithPath: "/Users/me/Gone.pdf"))])

        storage.missingPaths = ["/Users/me/Gone.pdf"]
        provider.displayedActivitiesChanged([ShelfProvider.itemsActivityID])

        #expect(collection?.items.first?.isUnavailable == true)
        #expect(collection?.items.first?.payload == nil)
    }

    @Test func itemActionsUseTheSystem() throws {
        let provider = makeProvider()
        engine.register(provider)
        drop([.file(URL(fileURLWithPath: "/Users/me/Report.pdf"))])
        let id = try #require(provider.collection.items.first?.id)
        let url = URL(fileURLWithPath: "/Users/me/Report.pdf")

        perform(.quickLook, on: id)
        perform(.reveal, on: id)
        perform(.copy, on: id)

        #expect(system.previewed == [[url]])
        #expect(system.revealed == [[url]])
        #expect(pasteboard.written == [.files([url])])
    }

    @Test func theCopyTileCopiesWithoutKeeping() {
        let provider = makeProvider()
        engine.register(provider)

        #expect(drop([.text("just copy")], on: .copy))

        #expect(pasteboard.written == [.text("just copy")])
        #expect(provider.collection.isEmpty)
        #expect(engine.activity(for: confirmationKey)?.title == "Copied")
    }

    @Test func theAirDropTileSendsWithoutKeeping() {
        let provider = makeProvider()
        engine.register(provider)

        #expect(drop([.url(URL(string: "https://apple.com")!)], on: .airDrop))

        #expect(system.airDropped == [[.url(URL(string: "https://apple.com")!)]])
        #expect(provider.collection.isEmpty)
    }

    @Test func removeAllWorksWhileTheShelfIsOff() {
        let provider = makeProvider()
        engine.register(provider)
        drop([.text("a")])
        engine.unregister(provider.source)

        provider.removeAll()

        #expect(provider.collection.isEmpty)
        #expect(storage.savedItems.isEmpty)
        #expect(!engine.acceptsDrops)
    }

    @Test func dropTilesAreFoundByLocation() {
        let frames: [NotchDrop.Target: CGRect] = [
            .copy: CGRect(x: 0, y: 0, width: 50, height: 50),
            .airDrop: CGRect(x: 60, y: 0, width: 50, height: 50),
        ]
        #expect(ShelfDropTargeting.target(at: CGPoint(x: 10, y: 10), tileFrames: frames) == .copy)
        #expect(ShelfDropTargeting.target(at: CGPoint(x: 70, y: 10), tileFrames: frames) == .airDrop)
        #expect(ShelfDropTargeting.target(at: CGPoint(x: 200, y: 10), tileFrames: frames) == .shelf)
        #expect(ShelfDropTargeting.target(at: nil, tileFrames: frames) == .shelf)
    }
}
