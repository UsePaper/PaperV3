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

    /// Links the bundled `paper` script into /usr/local/bin. The install can
    /// raise the system's authorisation sheet and block until it is answered,
    /// so it runs off the main thread.
    @objc func installCommandLineTool(_ sender: Any?) {
        guard let script = CommandLineTool.bundledScript() else {
            presentInstallOutcome(.failed(
                "The command ships inside the application bundle, and this "
                    + "copy of Paper has no bundle around it. Install Paper, "
                    + "then try again from there."
            ))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = CommandLineTool.install(script: script)
            DispatchQueue.main.async {
                self.presentInstallOutcome(outcome)
            }
        }
    }

    private func presentInstallOutcome(_ outcome: CommandLineTool.InstallOutcome) {
        let alert = NSAlert()
        switch outcome {
        case .cancelled:
            return
        case .installed:
            alert.messageText = "The paper command is installed."
            alert.informativeText = "Type paper notes.md in a terminal to open the file here."
        case .alreadyInstalled:
            alert.messageText = "The paper command is already installed."
            alert.informativeText = "\(CommandLineTool.linkPath) already points at this copy of Paper."
        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = "The paper command was not installed."
            alert.informativeText = message
        }
        alert.runModal()
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
