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

    override func makeWindowControllers() {
        let controller = EditorWindowController(model: model)
        addWindowController(controller)
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
