import AppKit
import XCTest
@testable import PaperApp

/// The find items of the Edit menu, validated on the document they land on.
@MainActor
final class FindMenuTests: XCTestCase {
    func testReplaceIsRefusedInReadingMode() {
        let document = MarkdownDocument()
        document.showReading(nil)

        let replace = NSMenuItem(title: "Find and Replace…",
                                 action: #selector(MarkdownDocument.performFindAction(_:)),
                                 keyEquivalent: "")
        replace.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        XCTAssertFalse(document.validateUserInterfaceItem(replace))

        let find = NSMenuItem(title: "Find…",
                              action: #selector(MarkdownDocument.performFindAction(_:)),
                              keyEquivalent: "")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        XCTAssertTrue(document.validateUserInterfaceItem(find))

        document.showPresentation(nil)
        XCTAssertTrue(document.validateUserInterfaceItem(replace))
    }
}
