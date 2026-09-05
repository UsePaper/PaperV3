import Foundation

/// "Install Command Line Tool…", the menu item behind `paper notes.md`.
///
/// The command itself is `scripts/paper`, which ships inside the bundle at
/// Contents/Resources/paper. Installing links to it rather than copying it,
/// so an app that updates updates its command with it, and a script found on
/// PATH always belongs to a Paper that is actually installed.
enum CommandLineTool {
    /// On PATH for every shell, and where an application that offers this
    /// puts its command. The directory belongs to root on a Mac that has not
    /// had Homebrew make it otherwise, which is why the write may need
    /// authorisation.
    static let linkPath = "/usr/local/bin/paper"

    /// What occupies the link's name right now.
    enum LinkState: Equatable {
        case absent
        /// A link to this very copy of Paper.
        case ours
        /// A link left by another copy: an older install, or one that has
        /// moved. Ours to replace, and replacing it is the whole point.
        case anotherPaper
        /// A link to something that is not a Paper. Not ours to delete.
        case foreignLink(String)
        /// Not a link, but something is there. Whatever it is, it is not
        /// ours to delete either.
        case occupied
    }

    static func linkState(at link: URL, script: URL) -> LinkState {
        let fileManager = FileManager.default
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path) else {
            return fileManager.fileExists(atPath: link.path) ? .occupied : .absent
        }
        // A relative destination resolves against the link's own directory.
        let target = URL(
            fileURLWithPath: destination,
            relativeTo: link.deletingLastPathComponent()
        ).standardizedFileURL
        if sameFile(target, script) { return .ours }
        if isPaperScript(target) { return .anotherPaper }
        return .foreignLink(target.path)
    }

    /// A link one Paper left for another:
    /// `<somewhere>/Paper.app/Contents/Resources/paper`.
    static func isPaperScript(_ target: URL) -> Bool {
        target.path.hasSuffix("Contents/Resources/paper")
    }

    /// Compares the files, not the text naming them, so `/tmp` and
    /// `/private/tmp` do not read as two different installs.
    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        a.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path
    }

    enum InstallOutcome: Equatable {
        case installed
        case alreadyInstalled
        /// The user dismissed the authorisation sheet. They know what they
        /// did, so there is nothing to tell them about it.
        case cancelled
        case failed(String)
    }

    /// The copy of the script inside this application, or nil when this
    /// binary runs without a bundle around it.
    static func bundledScript() -> URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("paper"),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    /// Blocking: the authorisation sheet stands there until the user answers
    /// it, so this must not run on the thread drawing the window.
    static func install(script: URL) -> InstallOutcome {
        let link = URL(fileURLWithPath: linkPath)
        switch linkState(at: link, script: script) {
        case .ours:
            return .alreadyInstalled
        case .foreignLink(let path):
            return .failed(
                "\(linkPath) already points at \(path). "
                    + "Remove it first if you want the Paper command there."
            )
        case .occupied:
            return .failed(
                "\(linkPath) already exists and is not a link. "
                    + "Remove it first if you want the Paper command there."
            )
        case .absent, .anotherPaper:
            break
        }

        // The unprivileged write first: on a machine where Homebrew owns
        // /usr/local/bin this succeeds, and asking for a password to do
        // something the user can already do is rude.
        do {
            try writeLink(at: link, to: script)
            return .installed
        } catch {
            return installWithPrivileges(script: script, link: link)
        }
    }

    private static func writeLink(at link: URL, to script: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Only ever a link of ours, which the checks above established.
        if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != nil {
            try fileManager.removeItem(at: link)
        }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: script)
    }

    /// `do shell script … with administrator privileges` raises the system's
    /// own authorisation sheet. The password goes to the system, nothing here
    /// sees it, and nothing here runs as root except the two commands below.
    private static func installWithPrivileges(script: URL, link: URL) -> InstallOutcome {
        let line = "mkdir -p \(shellQuoted(link.deletingLastPathComponent().path)) "
            + "&& ln -sfn \(shellQuoted(script.path)) \(shellQuoted(link.path))"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \(appleScriptQuoted(line)) with administrator privileges",
        ]
        let stderr = Pipe()
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return .failed(
                "Could not ask for permission to write \(linkPath): "
                    + error.localizedDescription
            )
        }
        // Read to EOF before waiting, so a chatty child can never fill the
        // pipe and stall against us.
        let complaintData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return .installed
        }
        let complaint = String(data: complaintData, encoding: .utf8) ?? ""
        if complaint.contains("-128") {
            return .cancelled
        }
        var message = complaint.trimmingCharacters(in: .whitespacesAndNewlines)
        let noise = "execution error: "
        if message.hasPrefix(noise) {
            message.removeFirst(noise.count)
        }
        return .failed("Could not write \(linkPath). \(message)")
    }

    /// One word for `sh`, whatever the path holds. A space, a quote or a
    /// semicolon in an application's name must not become shell syntax.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The same line again as an AppleScript string literal.
    static func appleScriptQuoted(_ text: String) -> String {
        "\""
            + text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }
}
