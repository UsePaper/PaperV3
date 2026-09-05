import AppKit

public enum PaperMain {
    /// The whole application. The executable target only calls this, so
    /// everything else in PaperApp stays internal and testable.
    public static func run() {
        // The document controller subclass must be instantiated before any
        // other code touches NSDocumentController.shared, or AppKit installs
        // the default controller and this one never takes effect.
        let documentController = PaperDocumentController()
        _ = documentController
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
