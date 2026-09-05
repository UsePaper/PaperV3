import AppKit
import SwiftUI

final class EditorWindowController: NSWindowController {
    /// Owns the floating outline of this window. Nothing else holds it.
    private var outlinePanel: OutlinePanelController?

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

        // The mode button rides in the native title bar, trailing, so the
        // system keeps drawing the bar and the traffic lights. The hosted
        // SwiftUI view observes the model, so a menu-driven mode change
        // redraws the icon the same as a press.
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        let button = NSHostingView(rootView: ModeButton(model: model))
        button.frame.size = button.fittingSize
        accessory.view = button
        window.addTitlebarAccessoryViewController(accessory)

        // The outline toggle rides beside it, for the same reasons.
        let outlineAccessory = NSTitlebarAccessoryViewController()
        outlineAccessory.layoutAttribute = .trailing
        let outlineButton = NSHostingView(rootView: OutlineButton(model: model))
        outlineButton.frame.size = outlineButton.fittingSize
        outlineAccessory.view = outlineButton
        window.addTitlebarAccessoryViewController(outlineAccessory)

        self.init(window: window)
        outlinePanel = OutlinePanelController(model: model, window: window)
    }
}
