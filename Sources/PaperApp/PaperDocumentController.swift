import AppKit
import UniformTypeIdentifiers

/// Supplies the document-type answers that normally come from Info.plist,
/// so `swift run` (an unbundled binary with no Info.plist) still opens and
/// saves documents. The bundled app answers the same questions from its
/// Info.plist, and the two must agree.
final class PaperDocumentController: NSDocumentController {
    static let markdownType = UTType.markdownDocument.identifier

    override var defaultType: String? {
        Self.markdownType
    }

    override func documentClass(forType typeName: String) -> AnyClass? {
        MarkdownDocument.self
    }

    override func typeForContents(of url: URL) throws -> String {
        Self.markdownType
    }

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        var contentTypes: [UTType] = [.markdownDocument]
        // Not every Markdown file carries the system's idea of the type, so
        // accept the common extensions and plain text as well.
        for ext in ["md", "markdown", "mdown", "mkd"] {
            if let type = UTType(filenameExtension: ext) {
                contentTypes.append(type)
            }
        }
        contentTypes.append(.plainText)
        openPanel.allowedContentTypes = contentTypes
        return super.runModalOpenPanel(openPanel, forTypes: nil)
    }
}
