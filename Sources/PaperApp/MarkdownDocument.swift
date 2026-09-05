import AppKit
import Combine
import PaperCore
import UniformTypeIdentifiers

/// One window, one Markdown file. The document owns the text model; the
/// editor view edits it through a binding and every change marks the
/// document dirty.
final class MarkdownDocument: NSDocument {
    /// LF text plus the line-ending style to restore on save.
    private var text = MarkdownText(content: "")
    /// The model the SwiftUI editor binds to. Created once so window and
    /// document always share the same object.
    let model = EditorModel()
    private var modelSubscription: AnyCancellable?

    override init() {
        super.init()
        modelSubscription = model.$content
            .dropFirst()
            .sink { [weak self] newContent in
                guard let self, self.text.content != newContent else { return }
                self.text.content = newContent
                self.updateChangeCount(.changeDone)
            }
    }

    override class var autosavesInPlace: Bool {
        false
    }

    // MARK: The status bar's view of the file

    /// AppKit may set the URL from a save on a background thread; the model
    /// is bound to views, so the write hops to the main thread when needed.
    override var fileURL: URL? {
        didSet {
            let name = fileURL?.lastPathComponent
            if Thread.isMainThread {
                model.fileName = name
            } else {
                DispatchQueue.main.async { self.model.fileName = name }
            }
        }
    }

    /// Both change-count paths funnel the flag to the model: this one for
    /// edits and reverts, the token one for completed saves.
    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        model.isDirty = isDocumentEdited
    }

    override func updateChangeCount(
        withToken changeCountToken: Any,
        for saveOperation: NSDocument.SaveOperationType
    ) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        model.isDirty = isDocumentEdited
    }

    override class var readableTypes: [String] {
        [UTType.markdownDocument.identifier, UTType.plainText.identifier]
    }

    override class var writableTypes: [String] {
        [UTType.markdownDocument.identifier]
    }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        "md"
    }

    /// The stored "opens in" preference. It is shared by every window, which
    /// is why it sits on the type, while the mode itself stays per window on
    /// the model. Read at window creation only: by design the setting does
    /// not reach into windows already open.
    static var startingModePreference: ViewMode {
        SettingsStore.shared.settings.defaultMode
    }

    /// The blank rule needs the text, so the document answers rather than
    /// the window controller.
    func startingMode(preferring preference: ViewMode) -> ViewMode {
        let blank = text.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return ViewMode.starting(preference: preference, blank: blank)
    }

    override func makeWindowControllers() {
        // Decided here, after any read, so the window never appears in one
        // mode and changes to another in front of the reader.
        model.mode = startingMode(preferring: Self.startingModePreference)
        let controller = EditorWindowController(model: model)
        addWindowController(controller)
    }

    // MARK: View menu actions

    /// The View menu items carry no target, so they land here through the
    /// responder chain and only the focused window's document moves.
    @objc func showPresentation(_ sender: Any?) {
        model.mode = .presentation
    }

    @objc func showReading(_ sender: Any?) {
        model.mode = .reading
    }

    @objc func toggleMarkdownSource(_ sender: Any?) {
        model.showsSource.toggle()
    }

    @objc func toggleOutline(_ sender: Any?) {
        // Source mode shows the raw text, which the outline cannot point
        // into. The button and the menu item are disabled then; this guard
        // covers the shortcut arriving anyway.
        guard !model.showsSource else { return }
        model.isOutlineVisible.toggle()
    }

    // MARK: Find

    /// The Edit menu's find items. They land here rather than on the text
    /// view, because the document is always in the responder chain while
    /// the text view is only there when focused, and because the engine's
    /// view needs the system find bar switched on before the action means
    /// anything. The sender's tag names the NSTextFinder action.
    @objc func performFindAction(_ sender: Any?) {
        guard let textView = editorTextView else { return }
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.performTextFinderAction(sender)
    }

    private var editorTextView: NSTextView? {
        guard let window = windowControllers.first?.window else { return nil }
        return EditorViewLocator.textView(in: window)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard let action = item.action else {
            return super.validateUserInterfaceItem(item)
        }
        let menuItem = item as? NSMenuItem
        switch action {
        case #selector(showPresentation(_:)):
            menuItem?.state = model.mode == .presentation ? .on : .off
            return true
        case #selector(showReading(_:)):
            menuItem?.state = model.mode == .reading ? .on : .off
            return true
        case #selector(toggleMarkdownSource(_:)):
            menuItem?.state = model.showsSource ? .on : .off
            return true
        case #selector(toggleOutline(_:)):
            menuItem?.state = model.isOutlineVisible ? .on : .off
            return !model.showsSource
        case #selector(performFindAction(_:)):
            // Replace writes into the document, and reading mode has put
            // the keyboard away. The text view refuses too, being not
            // editable; this keeps the menu honest about it.
            if menuItem?.tag == NSTextFinder.Action.showReplaceInterface.rawValue {
                return model.mode == .presentation
            }
            return true
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        text.encode()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        text = try MarkdownText.decode(data)
        // Reading can happen before or after the window exists (open vs
        // revert), so push the content into the model both ways.
        model.content = text.content
    }

    // MARK: The file underneath

    // NSDocument registers itself as the NSFilePresenter of its file, so
    // external writes arrive here without a watcher of our own, and its own
    // coordinated saves do not, because a coordinator does not notify the
    // presenter it was made for.

    /// Set while the sheet is up, so a burst of events asks one question.
    private var isAskingAboutExternalChange = false
    /// The disk date the user answered "Keep Mine" about, so the same write
    /// does not raise the question again.
    private var overruledDiskDate: Date?

    override nonisolated func presentedItemDidChange() {
        DispatchQueue.main.async { self.reactToExternalChange() }
    }

    override nonisolated func accommodatePresentedItemDeletion(
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        DispatchQueue.main.async { self.noteFileGone() }
        // Nothing here can object to the deletion. The buffer keeps the text.
        completionHandler(nil)
    }

    override nonisolated func presentedItemDidMove(to newURL: URL) {
        if Self.isInTrash(newURL) {
            // A move to the trash is a deletion to the person who did it, so
            // the document does not follow the file there. The old URL stays,
            // and a save writes the text back where it was.
            DispatchQueue.main.async { self.noteFileGone() }
        } else {
            // A plain rename or move. NSDocument follows the file, and the
            // fileURL observer renames the status bar with it.
            super.presentedItemDidMove(to: newURL)
        }
    }

    /// The whole decision, on the main thread. Internal so a test can drive
    /// it without a filesystem event.
    func reactToExternalChange() {
        guard let url = fileURL, !isAskingAboutExternalChange else { return }
        let diskDate = Self.modificationDate(at: url)
        let action = ExternalChange.action(
            isDirty: isDocumentEdited,
            knownModificationDate: fileModificationDate,
            diskModificationDate: diskDate
        )
        switch action {
        case .ignore:
            break
        case .gone:
            noteFileGone()
        case .reload:
            reloadFromDisk(url)
        case .ask:
            askAboutExternalChange(at: url, diskDate: diskDate)
        }
    }

    /// The file behind the buffer is gone, so the buffer is the only copy.
    /// The URL stays, which is the NSDocument convention, so a save puts the
    /// file back where it was. The dirty flag says there is work to save.
    func noteFileGone() {
        updateChangeCount(.changeDone)
    }

    private func reloadFromDisk(_ url: URL) {
        // Revert re-reads through the same read(from:) as an open, so the
        // model keeps its object identity and the window keeps its mode and
        // scroll state. If the read fails the buffer stands, and the stale
        // date check at save time still protects the file.
        try? revert(toContentsOf: url, ofType: fileType ?? PaperDocumentController.markdownType)
    }

    private func askAboutExternalChange(at url: URL, diskDate: Date?) {
        // A write the user already chose to overrule needs no second sheet.
        if let overruled = overruledDiskDate, let diskDate,
           abs(diskDate.timeIntervalSince(overruled)) <= ExternalChange.tolerance {
            return
        }
        guard let window = windowForSheet else { return }
        isAskingAboutExternalChange = true
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(url.lastPathComponent)\u{201D} changed on disk."
        alert.informativeText = "Another application changed the file, and this "
            + "window has unsaved changes of its own. Keeping yours leaves the "
            + "file as it is until you save."
        // Keep Mine first, so the Return key takes the choice that loses
        // nothing.
        alert.addButton(withTitle: "Keep Mine")
        alert.addButton(withTitle: "Reload From Disk")
        alert.beginSheetModal(for: window) { response in
            self.isAskingAboutExternalChange = false
            if response == .alertSecondButtonReturn {
                self.reloadFromDisk(url)
            } else {
                // The stale modification date stays in place on purpose, so
                // a later save still warns before overwriting the disk copy.
                self.overruledDiskDate = diskDate
            }
        }
    }

    /// Nil when the file has gone.
    nonisolated static func modificationDate(at url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    nonisolated static func isInTrash(_ url: URL) -> Bool {
        var relationship: FileManager.URLRelationship = .other
        do {
            try FileManager.default.getRelationship(
                &relationship,
                of: .trashDirectory,
                in: .userDomainMask,
                toItemAt: url
            )
            if relationship == .contains { return true }
        } catch {
            // No user trash to compare against. The path check below covers it.
        }
        // A volume's trash lives under /.Trashes, outside the user domain.
        return url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }
}
