import AppKit

extension NotchLayout {
    /// How far beyond each side of the notch an approaching drag opens the shelf.
    static let shelfActivationSideMargin: CGFloat = 90
    /// How far below the notch an approaching drag opens the shelf. The shelf must open before the
    /// pointer reaches the top edge: a drag resting there for about a second opens Mission Control's
    /// Spaces bar.
    static let shelfActivationBottomMargin: CGFloat = 44

    /// The region around the notch where an approaching drag opens the shelf. It lies inside the open
    /// shelf, so the pointer is over the shelf as soon as it opens.
    static func shelfActivationSize(notchSize: CGSize) -> CGSize {
        CGSize(
            width: notchSize.width + shelfActivationSideMargin * 2,
            height: notchSize.height + shelfActivationBottomMargin
        )
    }
}

/// Decides when a drag from another app has come near enough to the notch to open the shelf.
///
/// The window server delivers a drag only to the window under the pointer, and the resting notch is
/// small. To open the shelf before the pointer reaches the notch, the controller watches other apps'
/// mouse events and feeds them here. A drag-and-drop session writes the drag pasteboard, so a change
/// count that differs from the one at mouse-down means content (not a window or a text selection) is
/// being dragged. Pure, so the rules are unit tested.
struct DragApproachTracker {
    enum Action: Equatable, Sendable {
        case none
        /// Open the shelf.
        case open
        /// Close the shelf this tracker opened, unless the notch is receiving the drag itself.
        case close
    }

    /// Where an approaching drag opens the shelf, in screen coordinates.
    var activationRegion: CGRect
    /// The open shelf. Leaving it closes a shelf the tracker opened.
    var shelfRegion: CGRect

    /// The drag pasteboard's change count when the current gesture began.
    private var baseline: Int?
    /// The change count of a drag already found unusable, so its pasteboard isn't read again.
    private var rejectedChangeCount: Int?
    /// Whether the tracker opened the shelf for the current gesture.
    private(set) var isOpen = false

    init(activationRegion: CGRect = .null, shelfRegion: CGRect = .null) {
        self.activationRegion = activationRegion
        self.shelfRegion = shelfRegion
    }

    mutating func mouseDown(dragChangeCount: Int) -> Action {
        baseline = dragChangeCount
        rejectedChangeCount = nil
        return closeIfOpen()
    }

    /// - Parameters:
    ///   - dragChangeCount: Read only when the pointer is in the activation region.
    ///   - isAcceptable: Whether the dragged content could be dropped; read at most once per drag.
    mutating func mouseDragged(to location: CGPoint, dragChangeCount: () -> Int, isAcceptable: () -> Bool) -> Action {
        if isOpen {
            return shelfRegion.contains(location) ? .none : closeIfOpen()
        }
        guard let baseline, activationRegion.contains(location) else { return .none }
        let count = dragChangeCount()
        guard count != baseline, count != rejectedChangeCount else { return .none }
        guard isAcceptable() else {
            rejectedChangeCount = count
            return .none
        }
        isOpen = true
        return .open
    }

    mutating func mouseUp() -> Action {
        baseline = nil
        return closeIfOpen()
    }

    /// The shelf closed some other way (drop, the drag left it); forget that the tracker opened it.
    mutating func shelfClosed() {
        isOpen = false
    }

    private mutating func closeIfOpen() -> Action {
        guard isOpen else { return .none }
        isOpen = false
        return .close
    }
}

/// Feeds other apps' left-button mouse events (down, drag, up) to a `DragApproachTracker`.
///
/// Global monitors for mouse events need no permission. They receive nothing while the mouse is
/// still, and NotchDeck's own events (dragging an item out of the shelf) never reach them.
@MainActor
final class DragApproachMonitor {
    /// Called with the tracker's decision and the pointer location in screen coordinates.
    var onAction: ((DragApproachTracker.Action, CGPoint) -> Void)?

    private var tracker = DragApproachTracker()
    private var monitor: Any?
    private let dragPasteboard = NSPasteboard(name: .drag)

    var isRunning: Bool { monitor != nil }

    func update(activationRegion: CGRect, shelfRegion: CGRect) {
        tracker.activationRegion = activationRegion
        tracker.shelfRegion = shelfRegion
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        tracker = DragApproachTracker(activationRegion: tracker.activationRegion, shelfRegion: tracker.shelfRegion)
    }

    func shelfClosed() {
        tracker.shelfClosed()
    }

    private func handle(_ type: NSEvent.EventType) {
        let location = NSEvent.mouseLocation
        let pasteboard = dragPasteboard
        let action: DragApproachTracker.Action = switch type {
        case .leftMouseDown:
            tracker.mouseDown(dragChangeCount: pasteboard.changeCount)
        case .leftMouseDragged:
            tracker.mouseDragged(
                to: location,
                dragChangeCount: { pasteboard.changeCount },
                isAcceptable: { NotchDrop.canRead(pasteboard) }
            )
        case .leftMouseUp:
            tracker.mouseUp()
        default:
            .none
        }
        if action != .none {
            onAction?(action, location)
        }
    }
}
