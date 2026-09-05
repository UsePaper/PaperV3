import XCTest
@testable import PaperApp

/// Reproduces the dimmed Save item: typing must make NSDocument itself
/// report an edited document, not only the status bar's model flag.
final class DirtyFlagProbeTests: XCTestCase {
    @MainActor
    func testTypingMarksTheDocumentEdited() throws {
        let document = MarkdownDocument()
        document.model.content = "typed"

        let deadline = Date().addingTimeInterval(1)
        while !document.isDocumentEdited && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertTrue(document.model.isDirty, "the status bar flag should be set")
        XCTAssertTrue(document.isDocumentEdited, "NSDocument itself should be edited")
    }
}
