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

    override class var readableTypes: [String] {
        [UTType.markdownDocument.identifier, UTType.plainText.identifier]
    }

    override class var writableTypes: [String] {
        [UTType.markdownDocument.identifier]
    }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        "md"
    }

    /// The mode preference the settings will store one day. It is shared by
    /// every window, which is why it sits on the type, while the mode itself
    /// stays per window on the model.
    static let startingModePreference: ViewMode = .presentation

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
