import MarkdownEngine
import MarkdownEngineCodeBlocks
import SwiftUI

/// The whole content of a document window: the engine's editor, full bleed,
/// with the status bar along the bottom when the settings show it.
struct EditorScreen: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var settingsStore: SettingsStore

    init(model: EditorModel, settingsStore: SettingsStore = .shared) {
        self.model = model
        self.settingsStore = settingsStore
    }

    /// Shared across renders: the highlighter carries caches and a
    /// JavaScriptCore bridge that must not be rebuilt per keystroke.
    /// JetBrains Mono first, so the bundled face is the code face.
    /// Internal rather than private, because the diagram palette reads the
    /// code block background from the same highlighter the engine paints
    /// with.
    static let services = MarkdownEditorServices(
        syntaxHighlighter: HighlighterSwiftBridge(
            preferredFontNames: ["JetBrainsMono-Regular", "SF Mono", "Menlo"]
        )
    )

    var body: some View {
        let settings = settingsStore.settings
        VStack(spacing: 0) {
            editor(settings)
            if settings.statusbar {
                StatusBar(model: model)
            }
        }
    }

    private func editor(_ settings: Settings) -> some View {
        let fontName = settings.fontChoice.postScriptName
        let fontSize = CGFloat(settings.fontSize)
        let font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)

        var configuration = MarkdownEditorConfiguration.default
        configuration.services = Self.services
        // The engine takes both switches live: isEditable flips on any update
        // pass, and a rawSourceMode flip rebuilds the presentation in place.
        configuration.rawSourceMode = model.showsSource
        configuration.readingWidth = TypeMetrics.readingWidth(for: font, measure: settings.measure)
        configuration.paragraph.lineHeightExtraSpacing = TypeMetrics.extraLineSpacing(
            for: font,
            leading: settings.leading
        )
        // Correction is left off on purpose: it rewrites text on its own,
        // and in a Markdown buffer that reaches into code spans and paths.
        configuration.spellChecking = SpellCheckingPolicy(
            continuousSpellChecking: settings.spellcheck,
            grammarChecking: settings.spellcheck,
            automaticSpellingCorrection: false
        )

        return NativeTextViewWrapper(
            text: $model.content,
            configuration: configuration,
            fontName: fontName,
            fontSize: fontSize,
            documentId: model.documentId,
            isEditable: model.mode == .presentation,
            // The engine's copy-button report, borrowed as geometry for the
            // diagram overlay: it names every visible fenced block, keeps up
            // with scrolling and edits, and goes quiet about a block while
            // the caret is inside it.
            onCodeBlockSelectionChange: { [weak model] selections in
                model?.codeBlockSelections.send(selections)
            },
            // Across the rebuilds below: the wrapper records the offset on
            // teardown and asks for it back when the new editor is made.
            onPersistScrollOffset: { [weak model] id, offset in
                model?.scrollOffsets[id] = offset
            },
            restoreScrollOffset: { [weak model] id in
                model?.scrollOffsets[id]
            }
        )
        // The engine reads these values when the editor is made, not on
        // updates, so a change to any of them makes the editor anew. The
        // scroll position survives through the closures above; the undo
        // history does not, which is the price of the seam.
        .id("\(model.documentId)|\(fontName)|\(fontSize)|\(settings.measure)|\(settings.leading)|\(settings.spellcheck)")
        .ignoresSafeArea()
    }
}
