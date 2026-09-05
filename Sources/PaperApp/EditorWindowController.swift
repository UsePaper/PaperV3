import AppKit
import SwiftUI

final class EditorWindowController: NSWindowController {
    convenience init(model: EditorModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: EditorScreen(model: model))
        window.center()
        window.tabbingMode = .disallowed
        self.init(window: window)
    }
}
