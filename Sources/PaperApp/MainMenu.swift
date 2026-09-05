import AppKit

/// The main menu, built in code because the app has no nib.
enum MainMenu {
    static func build() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(appMenuItem())
        menu.addItem(fileMenuItem())
        menu.addItem(editMenuItem())
        menu.addItem(viewMenuItem())
        menu.addItem(windowMenuItem())
        return menu
    }

    private static func appMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Paper")
        submenu.addItem(withTitle: "About Paper",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Hide Paper",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = submenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        submenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit Paper",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        return wrapped(submenu)
    }

    private static func fileMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "File")
        submenu.addItem(withTitle: "New",
                        action: #selector(NSDocumentController.newDocument(_:)),
                        keyEquivalent: "n")
        submenu.addItem(withTitle: "Open…",
                        action: #selector(NSDocumentController.openDocument(_:)),
                        keyEquivalent: "o")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Close",
                        action: #selector(NSWindow.performClose(_:)),
                        keyEquivalent: "w")
        submenu.addItem(withTitle: "Save",
                        action: #selector(NSDocument.save(_:)),
                        keyEquivalent: "s")
        let saveAs = submenu.addItem(withTitle: "Save As…",
                                     action: #selector(NSDocument.saveAs(_:)),
                                     keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        submenu.addItem(withTitle: "Revert to Saved",
                        action: #selector(NSDocument.revertToSaved(_:)),
                        keyEquivalent: "")
        return wrapped(submenu)
    }

    private static func editMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Edit")
        submenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = submenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        submenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        submenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        submenu.addItem(withTitle: "Select All",
                        action: #selector(NSText.selectAll(_:)),
                        keyEquivalent: "a")
        return wrapped(submenu)
    }

    private static func viewMenuItem() -> NSMenuItem {
        // No targets: the actions travel the responder chain to the focused
        // window's document, which also checkmarks the current state.
        let submenu = NSMenu(title: "View")
        submenu.addItem(withTitle: "Markdown Source",
                        action: #selector(MarkdownDocument.toggleMarkdownSource(_:)),
                        keyEquivalent: "/")
        submenu.addItem(.separator())
        let presentation = submenu.addItem(withTitle: "Presentation",
                                           action: #selector(MarkdownDocument.showPresentation(_:)),
                                           keyEquivalent: "p")
        presentation.keyEquivalentModifierMask = [.command, .shift]
        let reading = submenu.addItem(withTitle: "Reading",
                                      action: #selector(MarkdownDocument.showReading(_:)),
                                      keyEquivalent: "r")
        reading.keyEquivalentModifierMask = [.command, .shift]
        return wrapped(submenu)
    }

    private static func windowMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Window")
        submenu.addItem(withTitle: "Minimize",
                        action: #selector(NSWindow.performMiniaturize(_:)),
                        keyEquivalent: "m")
        submenu.addItem(withTitle: "Zoom",
                        action: #selector(NSWindow.performZoom(_:)),
                        keyEquivalent: "")
        NSApp.windowsMenu = submenu
        return wrapped(submenu)
    }

    private static func wrapped(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = submenu
        return item
    }
}
