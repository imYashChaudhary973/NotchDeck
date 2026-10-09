import Foundation
import Testing
@testable import NotchDeck

struct DragApproachTrackerTests {
    let activation = CGRect(x: 100, y: 900, width: 400, height: 80)
    let shelf = CGRect(x: 50, y: 800, width: 500, height: 200)
    let inside = CGPoint(x: 300, y: 950)
    let nearby = CGPoint(x: 300, y: 850)
    let away = CGPoint(x: 300, y: 300)

    private func tracker() -> DragApproachTracker {
        DragApproachTracker(activationRegion: activation, shelfRegion: shelf)
    }

    @Test func aContentDragReachingTheRegionOpensTheShelf() {
        var tracker = tracker()
        #expect(tracker.mouseDown(dragChangeCount: 5) == .none)
        #expect(tracker.mouseDragged(to: away, dragChangeCount: { 6 }, isAcceptable: { true }) == .none)

        #expect(tracker.mouseDragged(to: inside, dragChangeCount: { 6 }, isAcceptable: { true }) == .open)
        #expect(tracker.isOpen)
    }

    @Test func movingAWindowOrSelectingTextDoesNotOpenTheShelf() {
        var tracker = tracker()
        _ = tracker.mouseDown(dragChangeCount: 5)

        // No drag session wrote the drag pasteboard.
        #expect(tracker.mouseDragged(to: inside, dragChangeCount: { 5 }, isAcceptable: { true }) == .none)
    }

    @Test func unusableContentIsCheckedOnce() {
        var tracker = tracker()
        _ = tracker.mouseDown(dragChangeCount: 5)
        var checks = 0

        for _ in 0..<3 {
            #expect(tracker.mouseDragged(to: inside, dragChangeCount: { 6 }, isAcceptable: { checks += 1; return false }) == .none)
        }
        #expect(checks == 1)
    }

    @Test func leavingTheShelfOrReleasingClosesIt() {
        var tracker = tracker()
        _ = tracker.mouseDown(dragChangeCount: 1)
        _ = tracker.mouseDragged(to: inside, dragChangeCount: { 2 }, isAcceptable: { true })

        // Still over the open shelf, even outside the activation region.
        #expect(tracker.mouseDragged(to: nearby, dragChangeCount: { 2 }, isAcceptable: { true }) == .none)
        #expect(tracker.mouseDragged(to: away, dragChangeCount: { 2 }, isAcceptable: { true }) == .close)
        #expect(!tracker.isOpen)

        _ = tracker.mouseDragged(to: inside, dragChangeCount: { 2 }, isAcceptable: { true })
        #expect(tracker.mouseUp() == .close)
    }

    @Test func aShelfClosedElsewhereIsNotClosedAgain() {
        var tracker = tracker()
        _ = tracker.mouseDown(dragChangeCount: 1)
        _ = tracker.mouseDragged(to: inside, dragChangeCount: { 2 }, isAcceptable: { true })

        tracker.shelfClosed()

        #expect(tracker.mouseUp() == .none)
    }

    @Test func dragsWithoutAMouseDownAreIgnored() {
        var tracker = tracker()
        #expect(tracker.mouseDragged(to: inside, dragChangeCount: { 9 }, isAcceptable: { true }) == .none)
    }

    @Test func theActivationRegionLiesAroundTheNotch() {
        let notch = CGSize(width: 200, height: 32)
        let size = NotchLayout.shelfActivationSize(notchSize: notch)
        #expect(size.width == 200 + NotchLayout.shelfActivationSideMargin * 2)
        #expect(size.height == 32 + NotchLayout.shelfActivationBottomMargin)
    }
}

@MainActor
final class DropAcceptingProvider: ActivityProvider {
    let source: ActivitySource
    let accepts: Bool
    var takes = true
    private(set) var drops: [NotchDrop.Target] = []

    init(source: ActivitySource, accepts: Bool = true) {
        self.source = source
        self.accepts = accepts
    }

    func start(publisher: ActivityPublisher) {}
    func stop() {}

    var acceptsDrops: Bool { accepts }

    func handleDrop(_ drop: NotchDrop) -> Bool {
        drops.append(drop.target)
        return takes
    }
}

@MainActor
struct DropRoutingTests {
    let engine = ActivityEngine(schedulesExpiry: false)

    @Test func acceptsDropsOnlyWhileAProviderDoes() {
        let plain = DropAcceptingProvider(source: .testA, accepts: false)
        let shelf = DropAcceptingProvider(source: .testB)

        engine.register(plain)
        #expect(!engine.acceptsDrops)
        engine.register(shelf)
        #expect(engine.acceptsDrops)
        engine.unregister(shelf.source)
        #expect(!engine.acceptsDrops)
    }

    @Test func dropsGoToTheFirstProviderThatTakesThem() {
        let declining = DropAcceptingProvider(source: .testA)
        declining.takes = false
        let taking = DropAcceptingProvider(source: .testB)
        engine.register(declining)
        engine.register(taking)

        #expect(engine.routeDrop(NotchDrop(items: [.text("x")], target: .copy)))

        #expect(declining.drops == [.copy])
        #expect(taking.drops == [.copy])
    }

    @Test func providersThatDontAcceptDropsAreSkipped() {
        let plain = DropAcceptingProvider(source: .testA, accepts: false)
        engine.register(plain)

        #expect(!engine.routeDrop(NotchDrop(items: [.text("x")], target: .shelf)))
        #expect(plain.drops.isEmpty)
    }

    @Test func emptyDropsAreNotRouted() {
        let shelf = DropAcceptingProvider(source: .testA)
        engine.register(shelf)

        #expect(!engine.routeDrop(NotchDrop(items: [], target: .shelf)))
        #expect(shelf.drops.isEmpty)
    }

    @Test func onlyWebLinksAreKept() {
        #expect(NotchDrop.isWebURL(URL(string: "https://apple.com")!))
        #expect(NotchDrop.isWebURL(URL(string: "HTTP://apple.com/x")!))
        #expect(!NotchDrop.isWebURL(URL(string: "file:///etc/passwd")!))
        #expect(!NotchDrop.isWebURL(URL(string: "javascript:alert(1)")!))
        #expect(!NotchDrop.isWebURL(URL(string: "https:///nohost")!))
    }
}

struct CollectionActionIDTests {
    @Test func itemActionIDsRoundTrip() {
        let id = CollectionContent.actionID("pin", item: "42")
        #expect(id == "pin:42")
        #expect(CollectionContent.itemAction(from: id).map { [$0.action, $0.item] } == ["pin", "42"])
    }

    @Test func onlyTheFirstColonSeparates() {
        #expect(CollectionContent.itemAction(from: "copy:a:b").map { [$0.action, $0.item] } == ["copy", "a:b"])
    }

    @Test func plainActionIDsAreNotItemActions() {
        #expect(CollectionContent.itemAction(from: "clear") == nil)
        #expect(CollectionContent.itemAction(from: ":42") == nil)
        #expect(CollectionContent.itemAction(from: "pin:") == nil)
    }

    @Test func colorComponentsAreClamped() {
        #expect(ColorComponents(red: 2, green: -1, blue: 0.5, alpha: 3) == ColorComponents(red: 1, green: 0, blue: 0.5, alpha: 1))
    }
}
