import Combine
import Foundation

/// The one settings object every window follows. PaperV2 ran a webview per
/// window and had to sync them through the file; here one process serves
/// every window, so a single observable store replaces that plumbing.
final class SettingsStore: ObservableObject {
    /// Swappable so tests can put a disk-free store in place.
    static var shared = SettingsStore(fileURL: SettingsStore.defaultFileURL)

    @Published private(set) var settings: Settings

    /// nil means no persistence, which is what tests want.
    private let fileURL: URL?
    private var pendingSave: DispatchWorkItem?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL {
            settings = Settings.parse(try? Data(contentsOf: fileURL))
        } else {
            settings = .default
        }
    }

    /// Where the settings live: the identifier from Info.plist, spelled out
    /// because a bare `swift run` binary has no bundle to ask.
    static var defaultFileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.rafi.paperv3", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    func update(_ mutate: (inout Settings) -> Void) {
        var changed = settings
        mutate(&changed)
        changed.clamp()
        guard changed != settings else { return }
        settings = changed
        scheduleSave()
    }

    /// One change rather than eight, so observers run once.
    func reset() {
        update { $0 = .default }
    }

    /// Debounced, because the text size slider fires on every tick and the
    /// file only needs the value the slider settles on.
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Called on quit as well, so a change made just before quitting lands.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try settings.encode().write(to: fileURL, options: .atomic)
        } catch {
            // Settings that fail to persist still work for this run. There
            // is no better place to surface a disk error from a debounce.
            NSLog("Paper: could not write settings: \(error)")
        }
    }
}
