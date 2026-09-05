import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import PaperApp

/// The Edit menu's Copy Markdown: the whole document to the pasteboard as
/// plain text. A named pasteboard stands in for the general one, so running
/// the tests never touches what the user last copied.
@MainActor
final class CopyMarkdownTests: XCTestCase {
    private let markdownType = UTType.markdownDocument.identifier

    private func freshPasteboard(_ name: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PaperTests.\(name)"))
        pasteboard.clearContents()
        return pasteboard
    }

    func testCopiesTheWholeDocumentExactly() throws {
        let source = "# Title\n\nBody with *emphasis*.\n\n```mermaid\ngraph TD\n  A --> B\n```\n"
        let document = MarkdownDocument()
        try document.read(from: Data(source.utf8), ofType: markdownType)

        let pasteboard = freshPasteboard("whole")
        document.copyMarkdown(to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), source)
    }

    func testCopiesTheEditedTextNotTheFile() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("start\n".utf8), ofType: markdownType)
        document.model.content = "start edited\n"

        let pasteboard = freshPasteboard("edited")
        document.copyMarkdown(to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "start edited\n")
    }

    func testCopiesLFWhateverTheFileStyleWas() throws {
        // The pasteboard carries the in-memory form. The CRLF style is a
        // property of the file on disk, restored on save, not of the text.
        let document = MarkdownDocument()
        try document.read(from: Data("one\r\ntwo\r\n".utf8), ofType: markdownType)

        let pasteboard = freshPasteboard("crlf")
        document.copyMarkdown(to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "one\ntwo\n")
    }
}
