import XCTest
@testable import PaperCore

final class MarkdownTextTests: XCTestCase {
    func testStripsUTF8BOM() throws {
        let data = Data([0xEF, 0xBB, 0xBF] + Array("# Hello\n".utf8))
        let text = try MarkdownText.decode(data)
        XCTAssertEqual(text.content, "# Hello\n")
        XCTAssertEqual(text.lineEnding, .lf)
    }

    func testNormalizesCRLFAndWritesItBack() throws {
        let original = "# Title\r\n\r\nBody line.\r\n"
        let text = try MarkdownText.decode(Data(original.utf8))
        XCTAssertEqual(text.content, "# Title\n\nBody line.\n")
        XCTAssertEqual(text.lineEnding, .crlf)
        XCTAssertEqual(text.encode(), Data(original.utf8))
    }

    func testLFFileStaysLF() throws {
        let original = "line one\nline two\n"
        let text = try MarkdownText.decode(Data(original.utf8))
        XCTAssertEqual(text.lineEnding, .lf)
        XCTAssertEqual(text.encode(), Data(original.utf8))
    }

    func testEditedContentKeepsOriginalLineEndingStyle() throws {
        var text = try MarkdownText.decode(Data("a\r\nb\r\n".utf8))
        text.content += "c\n"
        XCTAssertEqual(text.encode(), Data("a\r\nb\r\nc\r\n".utf8))
    }

    func testRejectsNonUTF8() {
        XCTAssertThrowsError(try MarkdownText.decode(Data([0xFF, 0xFE, 0x00])))
    }
}
