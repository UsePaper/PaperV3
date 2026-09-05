import AppKit
import Combine
import MarkdownEngineCodeBlocks

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var themeSubscription: AnyCancellable?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        followThemeSetting()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A change made just before quitting must not die in the debounce.
        SettingsStore.shared.saveNow()
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    /// The theme is the application's appearance. The engine's own colors
    /// are dynamic system colors, so they follow along without being told;
    /// the code block highlighter caches by appearance and is told.
    private func followThemeSetting() {
        themeSubscription = SettingsStore.shared.$settings
            .map(\.theme)
            .removeDuplicates()
            .sink { theme in
                NSApp.appearance = switch theme {
                case .system: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                }
                // The highlighter only watches the system-wide switch, so an
                // override here would leave stale code colors without this.
                NotificationCenter.default.post(
                    name: .markdownEngineHighlighterDidChangeAppearance,
                    object: nil
                )
            }
    }
}
