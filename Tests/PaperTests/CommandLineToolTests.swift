import XCTest
@testable import PaperApp

/// The link-state classification behind "Install Command Line Tool…",
/// exercised against real links in a temp directory, and the quoting that
/// keeps a path from becoming shell syntax.
final class CommandLineToolTests: XCTestCase {
    private var dir: URL!
    private var script: URL!
    private var link: URL!

    override func setUpWithError() throws {
        // Under /private/tmp on purpose, so the alias test below can name
        // the same script as /tmp/… and mean the same file.
        dir = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("paper-cli-\(UUID().uuidString)")
        // A realistic bundle shape, so the another-Paper check has something
        // honest to recognise.
        let resources = dir.appendingPathComponent("Paper.app/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        script = resources.appendingPathComponent("paper")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        link = dir.appendingPathComponent("bin/paper")
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testNothingThereIsAbsent() {
        XCTAssertEqual(CommandLineTool.linkState(at: link, script: script), .absent)
    }

    func testLinkToThisCopyIsOurs() throws {
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: script)
        XCTAssertEqual(CommandLineTool.linkState(at: link, script: script), .ours)
    }

    func testAliasedLinkIsStillOurs() throws {
        // The link text names the script through /tmp while we hold the
        // /private/tmp name. Same file, so the same install.
        let aliased = URL(fileURLWithPath: script.path.replacingOccurrences(
            of: "/private/tmp/",
            with: "/tmp/"
        ))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: aliased)
        XCTAssertEqual(CommandLineTool.linkState(at: link, script: script), .ours)
    }

    func testAnotherPaperBundleIsReplaceable() throws {
        let other = dir.appendingPathComponent("Elsewhere/Paper.app/Contents/Resources/paper")
        try FileManager.default.createDirectory(
            at: other.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: other)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        XCTAssertEqual(CommandLineTool.linkState(at: link, script: script), .anotherPaper)
    }

    func testForeignLinkIsRefused() throws {
        let foreign = dir.appendingPathComponent("someone-elses-paper")
        try Data("#!/bin/sh\n".utf8).write(to: foreign)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: foreign)
        guard case .foreignLink = CommandLineTool.linkState(at: link, script: script) else {
            return XCTFail("A foreign link must not read as ours or as another Paper's.")
        }
    }

    func testPlainFileIsOccupied() throws {
        try Data("not a link\n".utf8).write(to: link)
        XCTAssertEqual(CommandLineTool.linkState(at: link, script: script), .occupied)
    }

    func testRecognisesAnotherCopysScript() {
        XCTAssertTrue(CommandLineTool.isPaperScript(
            URL(fileURLWithPath: "/Applications/Paper.app/Contents/Resources/paper")
        ))
        XCTAssertTrue(CommandLineTool.isPaperScript(
            URL(fileURLWithPath: "/Users/a/build/Paper.app/Contents/Resources/paper")
        ))
        XCTAssertFalse(CommandLineTool.isPaperScript(URL(fileURLWithPath: "/opt/paper/bin/paper")))
        XCTAssertFalse(CommandLineTool.isPaperScript(URL(fileURLWithPath: "/usr/local/bin/paper")))
    }

    // MARK: Quoting

    func testQuotesAPlainPath() {
        XCTAssertEqual(
            CommandLineTool.shellQuoted("/Applications/Paper.app"),
            "'/Applications/Paper.app'"
        )
    }

    func testSurvivesASpace() {
        XCTAssertEqual(
            CommandLineTool.shellQuoted("/Users/a b/Paper.app"),
            "'/Users/a b/Paper.app'"
        )
    }

    /// The one that ends the quoting if it is not handled: close, escape,
    /// reopen.
    func testSurvivesAQuote() {
        XCTAssertEqual(
            CommandLineTool.shellQuoted("/Users/o'brien/Paper.app"),
            "'/Users/o'\\''brien/Paper.app'"
        )
    }

    func testShellSyntaxStaysText() {
        XCTAssertEqual(CommandLineTool.shellQuoted("/tmp/a; rm -rf /"), "'/tmp/a; rm -rf /'")
    }

    func testAppleScriptEscapesItsOwnQuotes() {
        XCTAssertEqual(
            CommandLineTool.appleScriptQuoted(#"ln -s "a" b"#),
            #""ln -s \"a\" b""#
        )
        XCTAssertEqual(CommandLineTool.appleScriptQuoted(#"a\b"#), #""a\\b""#)
    }
}
