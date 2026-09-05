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
}
