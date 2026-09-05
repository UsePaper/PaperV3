import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import PaperApp
@testable import PaperCore

/// The external change rules: a clean buffer reloads, a dirty one asks, a
/// file that is gone leaves the buffer as the only copy, and our own save
/// never raises the question.
final class ExternalChangeTests: XCTestCase {
    private let known = Date(timeIntervalSinceReferenceDate: 1_000)

    func testCleanBufferReloads() {
        let action = ExternalChange.action(
            isDirty: false,
            knownModificationDate: known,
            diskModificationDate: known.addingTimeInterval(5)
        )
        XCTAssertEqual(action, .reload)
    }

    func testDirtyBufferAsks() {
        let action = ExternalChange.action(
            isDirty: true,
            knownModificationDate: known,
            diskModificationDate: known.addingTimeInterval(5)
        )
        XCTAssertEqual(action, .ask)
    }

    func testGoneFileWinsOverDirtiness() {
        for dirty in [false, true] {
            let action = ExternalChange.action(
                isDirty: dirty,
                knownModificationDate: known,
                diskModificationDate: nil
            )
            XCTAssertEqual(action, .gone)
        }
    }

    func testOwnSaveIsIgnoredWithinTolerance() {
        for offset in [0, ExternalChange.tolerance, -ExternalChange.tolerance] {
            let action = ExternalChange.action(
                isDirty: true,
                knownModificationDate: known,
                diskModificationDate: known.addingTimeInterval(offset)
            )
            XCTAssertEqual(action, .ignore)
        }
    }

    func testBackdatedFileStillCounts() {
        // A restored backup moves the date backwards. That is a change too.
        let action = ExternalChange.action(
            isDirty: false,
            knownModificationDate: known,
            diskModificationDate: known.addingTimeInterval(-60)
        )
        XCTAssertEqual(action, .reload)
    }

    func testUnknownDateNeverIgnores() {
        let action = ExternalChange.action(
            isDirty: false,
            knownModificationDate: nil,
            diskModificationDate: known
        )
        XCTAssertEqual(action, .reload)
    }
}

/// The document-side wiring, exercised headless against real temp files.
@MainActor
final class DocumentExternalChangeTests: XCTestCase {
    private let markdownType = UTType.markdownDocument.identifier

    private func makeTempFile(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paper-watch-\(UUID().uuidString).md")
        try Data(content.utf8).write(to: url)
        return url
    }

    func testCleanBufferReloadsSilently() throws {
        let url = try makeTempFile("before\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try MarkdownDocument(contentsOf: url, ofType: markdownType)

        // Push the write clearly outside the tolerance window.
        try Data("after\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: url.path
        )

        document.reactToExternalChange()
        XCTAssertEqual(document.model.content, "after\n")
        XCTAssertFalse(document.isDocumentEdited)
    }

    func testGoneFileMarksBufferUnsaved() throws {
        let url = try makeTempFile("only copy\n")
        let document = try MarkdownDocument(contentsOf: url, ofType: markdownType)
        try FileManager.default.removeItem(at: url)

        document.reactToExternalChange()
        XCTAssertTrue(document.isDocumentEdited)
        XCTAssertTrue(document.model.isDirty)
        // The URL stays, so a save writes the text back where it was.
        XCTAssertEqual(document.fileURL, url)
        XCTAssertEqual(document.model.content, "only copy\n")
    }

    func testOwnSaveLandsInsideTheIgnoreTolerance() throws {
        let url = try makeTempFile("start\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try MarkdownDocument(contentsOf: url, ofType: markdownType)
        document.model.content = "start edited\n"

        // The synchronous save path. It updates fileModificationDate the way
        // a menu save does.
        try document.writeSafely(to: url, ofType: markdownType, for: .saveOperation)

        let action = ExternalChange.action(
            isDirty: document.isDocumentEdited,
            knownModificationDate: document.fileModificationDate,
            diskModificationDate: MarkdownDocument.modificationDate(at: url)
        )
        XCTAssertEqual(action, .ignore)
    }

    func testTrashDetection() {
        XCTAssertTrue(MarkdownDocument.isInTrash(
            URL(fileURLWithPath: NSHomeDirectory() + "/.Trash/notes.md")
        ))
        XCTAssertTrue(MarkdownDocument.isInTrash(
            URL(fileURLWithPath: "/Volumes/USB/.Trashes/501/notes.md")
        ))
        XCTAssertFalse(MarkdownDocument.isInTrash(
            URL(fileURLWithPath: "/Users/someone/notes.md")
        ))
    }
}
