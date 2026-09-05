import Combine
import CoreGraphics
import Foundation
import MarkdownEngine

/// The observable text the editor view binds to. The document subscribes to
/// it for dirty tracking and writes into it on read and revert.
final class EditorModel: ObservableObject {
    @Published var content: String = ""
    /// Per window, never shared: another window's mode is none of ours.
    @Published var mode: ViewMode = .presentation
    /// The raw Markdown escape hatch. Orthogonal to the mode, so reading
    /// keeps a source view read-only instead of turning it off.
    @Published var showsSource: Bool = false
    /// Whether the outline panel is out. A toggle, not a setting: per
    /// window, and remembered by nobody.
    @Published var isOutlineVisible: Bool = false
    /// What the status bar names: the saved file, or nil while unsaved.
    @Published var fileName: String?
    /// Whether the buffer differs from the file. The document writes it,
    /// because only the document knows; the status bar reads it.
    @Published var isDirty: Bool = false
    /// Scopes the engine's per-document undo stack to this window.
    let documentId = UUID().uuidString
    /// Where the reader was, kept across the editor rebuild a settings
    /// change forces. Not published: scrolling is not a model change.
    var scrollOffsets: [String: CGFloat] = [:]
    /// The engine's report of where the visible code blocks sit, for the
    /// diagram overlay. A subject rather than a published property, so a
    /// scroll tick never re-renders the SwiftUI tree.
    let codeBlockSelections = CurrentValueSubject<[CodeBlockSelection], Never>([])
}
