import AppKit
import XCTest
@testable import PaperApp

/// The withdrawal rules, headless: what event sets which fuse, and when a
/// pointer over the panel holds it open.
final class OutlineFuseTests: XCTestCase {
    func testOpeningLightsTheIdleFuse() {
        var fuse = OutlineFuse()
        XCTAssertEqual(fuse.delay(after: .opened), OutlineFuse.idleDelay)
    }

    func testHoveringHoldsThePanelOpen() {
        var fuse = OutlineFuse()
        XCTAssertNil(fuse.delay(after: .hoverBegan))
        XCTAssertNil(fuse.delay(after: .activity))
        XCTAssertEqual(fuse.delay(after: .hoverEnded), OutlineFuse.idleDelay)
    }

    func testAClickLightsTheShortFuseEvenUnderThePointer() {
        var fuse = OutlineFuse()
        _ = fuse.delay(after: .hoverBegan)
        XCTAssertEqual(fuse.delay(after: .entryClicked), OutlineFuse.clickedDelay)
    }

    func testActivityAfterAClickRestoresTheIdleRule() {
        var fuse = OutlineFuse()
        _ = fuse.delay(after: .entryClicked)
        XCTAssertEqual(fuse.delay(after: .activity), OutlineFuse.idleDelay)
        _ = fuse.delay(after: .hoverBegan)
        XCTAssertNil(fuse.delay(after: .activity))
    }
}

/// How the outline toggle meets the modes, exercised on the document the
/// menu items land on.
@MainActor
final class OutlineToggleTests: XCTestCase {
    func testToggleFlipsThePanel() {
        let document = MarkdownDocument()
        document.toggleOutline(nil)
        XCTAssertTrue(document.model.isOutlineVisible)
        document.toggleOutline(nil)
        XCTAssertFalse(document.model.isOutlineVisible)
    }

    func testSourceModeRefusesTheToggle() {
        let document = MarkdownDocument()
        document.toggleMarkdownSource(nil)
        document.toggleOutline(nil)
        XCTAssertFalse(document.model.isOutlineVisible)

        let item = NSMenuItem(title: "Outline",
                              action: #selector(MarkdownDocument.toggleOutline(_:)),
                              keyEquivalent: "")
        XCTAssertFalse(document.validateUserInterfaceItem(item))
    }

    func testValidationChecksTheOpenPanel() {
        let document = MarkdownDocument()
        document.toggleOutline(nil)
        let item = NSMenuItem(title: "Outline",
                              action: #selector(MarkdownDocument.toggleOutline(_:)),
                              keyEquivalent: "")
        XCTAssertTrue(document.validateUserInterfaceItem(item))
        XCTAssertEqual(item.state, .on)
    }

    /// The controller, not the document, pulls the panel in when source
    /// mode opens, so this one needs the real window wiring.
    func testOpeningSourceModeClosesThePanel() {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        document.toggleOutline(nil)
        XCTAssertTrue(document.model.isOutlineVisible)

        document.toggleMarkdownSource(nil)
        let deadline = Date().addingTimeInterval(1)
        while document.model.isOutlineVisible && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(document.model.isOutlineVisible)

        document.windowControllers.forEach { $0.close() }
    }
}
