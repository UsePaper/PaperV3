import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import PaperApp
@testable import PaperCore

/// The NSDocument plumbing, exercised headless: read fills the model,
/// edits mark the document dirty, and save data restores the original
/// line-ending style.
@MainActor
final class MarkdownDocumentTests: XCTestCase {
    private let markdownType = UTType.markdownDocument.identifier

    func testReadFillsModelAndNormalizes() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("# Title\r\n\r\nBody\r\n".utf8), ofType: markdownType)
        XCTAssertEqual(document.model.content, "# Title\n\nBody\n")
    }

    func testEditMarksDocumentDirty() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("start\n".utf8), ofType: markdownType)
        XCTAssertFalse(document.isDocumentEdited)
        document.model.content = "start edited\n"
        XCTAssertTrue(document.isDocumentEdited)
    }

    func testSaveDataKeepsCRLF() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("one\r\ntwo\r\n".utf8), ofType: markdownType)
        document.model.content = "one\ntwo\nthree\n"
        let data = try document.data(ofType: markdownType)
        XCTAssertEqual(data, Data("one\r\ntwo\r\nthree\r\n".utf8))
    }

    func testUntouchedDocumentSavesOriginalBytes() throws {
        let original = Data("plain\nlf\nfile\n".utf8)
        let document = MarkdownDocument()
        try document.read(from: original, ofType: markdownType)
        XCTAssertEqual(try document.data(ofType: markdownType), original)
    }
}
