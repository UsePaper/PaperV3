import MarkdownEngine
import MarkdownEngineCodeBlocks
import SwiftUI

/// The whole content of a document window: the engine's editor, full bleed.
struct EditorScreen: View {
    @ObservedObject var model: EditorModel

    private static let configuration: MarkdownEditorConfiguration = {
        var configuration = MarkdownEditorConfiguration.default
        configuration.services = MarkdownEditorServices(
            syntaxHighlighter: HighlighterSwiftBridge()
        )
        return configuration
    }()

    var body: some View {
        NativeTextViewWrapper(
            text: $model.content,
            configuration: Self.configuration,
            documentId: model.documentId
        )
        .ignoresSafeArea()
    }
}
