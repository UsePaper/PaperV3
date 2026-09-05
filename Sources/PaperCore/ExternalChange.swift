import Foundation

/// What a report from the file watcher means for one window's buffer.
public enum ExternalChangeAction: Equatable, Sendable {
    /// Our own save coming back, or no real change.
    case ignore
    /// The buffer is clean, so the new text can simply replace it.
    case reload
    /// The buffer is dirty. Only the user can choose between the versions.
    case ask
    /// The file was deleted or moved away. The buffer is all that is left.
    case gone
}

/// Decides what a change on disk means. The rules come from PaperV2: a clean
/// buffer reloads without a question, a dirty one asks, and a file that is
/// gone leaves the buffer as the only copy.
public enum ExternalChange {
    /// Filesystem timestamps are coarse, so dates this close count as the
    /// same write.
    public static let tolerance: TimeInterval = 0.001

    /// `diskModificationDate` is nil when the file has gone.
    /// `knownModificationDate` is the date as of the last read or write.
    public static func action(
        isDirty: Bool,
        knownModificationDate: Date?,
        diskModificationDate: Date?
    ) -> ExternalChangeAction {
        guard let diskDate = diskModificationDate else { return .gone }
        if let knownDate = knownModificationDate,
           abs(diskDate.timeIntervalSince(knownDate)) <= tolerance {
            return .ignore
        }
        return isDirty ? .ask : .reload
    }
}
