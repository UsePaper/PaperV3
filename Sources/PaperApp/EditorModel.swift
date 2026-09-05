import Combine
import Foundation

/// The observable text the editor view binds to. The document subscribes to
/// it for dirty tracking and writes into it on read and revert.
final class EditorModel: ObservableObject {
    @Published var content: String = ""
    /// Per window, never shared: another window's mode is none of ours.
    @Published var mode: ViewMode = .presentation
    /// The raw Markdown escape hatch. Orthogonal to the mode, so reading
    /// keeps a source view read-only instead of turning it off.
    @Published var showsSource: Bool = false
    /// Scopes the engine's per-document undo stack to this window.
    let documentId = UUID().uuidString
}
