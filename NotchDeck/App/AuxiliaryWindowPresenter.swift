import AppKit
import SwiftUI

/// Shows ordinary app windows (Settings, Debug) from an accessory app.
///
/// Managed in AppKit rather than as SwiftUI scenes so that nothing opens at launch and
/// windows reliably come to the front even though NotchDeck has no Dock icon.
@MainActor
final class AuxiliaryWindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, @ViewBuilder content: () -> Content) {
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
        } else {
            window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            windows[id] = window
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
