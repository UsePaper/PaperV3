import Combine
import Foundation

/// The observable text the editor view binds to. The document subscribes to
/// it for dirty tracking and writes into it on read and revert.
final class EditorModel: ObservableObject {
    @Published var content: String = ""
    /// Scopes the engine's per-document undo stack to this window.
    let documentId = UUID().uuidString
}
