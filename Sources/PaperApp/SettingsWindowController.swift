import AppKit
import SwiftUI

/// One settings window for the whole application, the way a Mac application
/// does it: every document window follows the store, so there is nothing a
/// second copy of the form could show.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private convenience init() {
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsView(store: .shared)
        ))
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        // Closed is hidden: the one instance keeps its window for next time.
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }
}
