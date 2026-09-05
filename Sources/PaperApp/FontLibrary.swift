import AppKit
import CoreText

/// The bundled writing faces, registered for this process at launch.
///
/// The files are the same subset variable woff2 that PaperV2 ships, kept as
/// woff2 because CoreText on current macOS registers them directly. Each
/// family is under the SIL Open Font License, whose one obligation is that
/// the licence ships with the font: the texts sit beside the files.
enum FontLibrary {
    /// Idempotent, and safe to call before the application object exists.
    static func registerBundledFonts() {
        guard let fontsDirectory = Bundle.module.url(forResource: "Fonts", withExtension: nil) else {
            NSLog("Paper: the bundled fonts are missing")
            return
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: fontsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in files where url.pathExtension == "woff2" {
            var registrationError: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError) {
                // A face that fails leaves its setting resolving to the
                // system font, which is a readable page rather than a crash.
                let reason = registrationError?.takeRetainedValue().localizedDescription ?? "unknown"
                NSLog("Paper: could not register \(url.lastPathComponent): \(reason)")
            }
        }
    }
}
