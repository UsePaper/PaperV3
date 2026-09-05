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
        // The engine takes both switches live: isEditable flips on any update
        // pass, and a rawSourceMode flip rebuilds the presentation in place.
        var configuration = Self.configuration
        configuration.rawSourceMode = model.showsSource
        return NativeTextViewWrapper(
            text: $model.content,
            configuration: configuration,
            documentId: model.documentId,
            isEditable: model.mode == .presentation
        )
        .ignoresSafeArea()
    }
}
