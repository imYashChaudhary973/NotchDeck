import AppKit
import SwiftUI

/// Hosts the SwiftUI notch surface and translates AppKit input into notch events.
///
/// Only the visible surface (`interactiveSize`, top-centered) counts as "inside":
/// hover tracking uses a single tracking area sized to it, and clicks elsewhere in
/// the panel are reported as outside clicks.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onClickOutside: (() -> Void)?
    /// Called when a drag enters or moves, with its location in this view and an item description.
    var onDragUpdated: ((CGPoint, String) -> Void)?
    var onDragExited: (() -> Void)?
    var onDrop: (() -> Void)?

    /// Size of the visible notch surface. Updating it rebuilds the hover tracking area.
    var interactiveSize: CGSize = .zero {
        didSet {
            if interactiveSize != oldValue {
                updateTrackingAreas()
            }
        }
    }

    private var hoverTrackingArea: NSTrackingArea?
    private var isPointerInside = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png, .pdf])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The visible surface in this view's coordinate space.
    var interactiveRect: CGRect {
        let size = CGSize(width: min(interactiveSize.width, bounds.width), height: min(interactiveSize.height, bounds.height))
        let y = isFlipped ? bounds.minY : bounds.maxY - size.height
        return CGRect(x: bounds.midX - size.width / 2, y: y, width: size.width, height: size.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTrackingAreas()
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: interactiveRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        reconcilePointerLocation()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard event.trackingArea === hoverTrackingArea else { return }
        setPointerInside(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard event.trackingArea === hoverTrackingArea else { return }
        setPointerInside(false)
    }

    /// Tracking areas don't report enter/exit when they are replaced under a stationary pointer,
    /// so compare against the real pointer location whenever the surface changes size.
    func reconcilePointerLocation() {
        // `mouseLocationOutsideOfEventStream` is stale for a panel that hasn't received events yet,
        // so use the global pointer location.
        guard let window, window.isVisible else { return }
        let location = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        setPointerInside(interactiveRect.contains(location))
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        if inside {
            onPointerEntered?()
        } else {
            onPointerExited?()
        }
    }

    // MARK: Clicks

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard interactiveRect.contains(location) else {
            onClickOutside?()
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: Drag and drop

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        reportDrag(sender)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        reportDrag(sender)
        return .copy
    }

    private func reportDrag(_ sender: any NSDraggingInfo) {
        let location = convert(sender.draggingLocation, from: nil)
        // SwiftUI's coordinate space is top-left based.
        let topLeft = isFlipped ? location : CGPoint(x: location.x, y: bounds.height - location.y)
        onDragUpdated?(topLeft, Self.describe(sender.draggingPasteboard))
    }

    /// A short description of dragged content, e.g. a file name or "3 items". Never reads file contents.
    static func describe(_ pasteboard: NSPasteboard) -> String {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        let files = urls.filter(\.isFileURL)
        if files.count == 1 { return files[0].lastPathComponent }
        if files.count > 1 { return "\(files.count) items" }
        if let url = urls.first { return url.host() ?? "Link" }
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) { return "Image" }
        if pasteboard.string(forType: .string) != nil { return "Text" }
        return "Item"
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragExited?()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        true
    }

    /// Phase 1 only detects drags. Items are not accepted until the File Shelf exists (Phase 4),
    /// so the drop is refused and the dragged item returns to its source.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDrop?()
        return false
    }
}
