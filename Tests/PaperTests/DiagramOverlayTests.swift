import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import PaperApp

/// The whole diagram path through a real document window: the fence is
/// found, drawn offscreen, and laid over its code block, while an ordinary
/// fence is left alone.
@MainActor
final class DiagramOverlayTests: XCTestCase {
    func testADiagramIsDrawnOverItsFenceAndCodeIsNot() throws {
        _ = NSApplication.shared
        let source = "# Title\n\n```mermaid\ngraph TD\n  A --> B\n```\n\n```js\nconst x = 1;\n```\n"
        let document = MarkdownDocument()
        try document.read(from: Data(source.utf8), ofType: UTType.markdownDocument.identifier)
        document.makeWindowControllers()

        let window = try XCTUnwrap(document.windowControllers.first?.window)
        window.isReleasedWhenClosed = false
        defer {
            window.close()
            document.close()
        }
        window.contentView?.layoutSubtreeIfNeeded()

        // Drawing is asynchronous: the fence has to reach the web view and
        // come back as a snapshot. Pump the loop until the image lands.
        let deadline = Date().addingTimeInterval(20)
        var drawn: DiagramOverlayView?
        while Date() < deadline, drawn == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if let contentView = window.contentView {
                drawn = Self.overlays(in: contentView).first { $0.image != nil }
            }
        }

        let overlay = try XCTUnwrap(drawn, "no drawn overlay appeared in the window")
        XCTAssertFalse(overlay.isHidden)
        XCTAssertGreaterThan(overlay.frame.width, 0)
        XCTAssertGreaterThan(overlay.frame.height, 0)
        XCTAssertEqual(overlay.source, "graph TD\n  A --> B")

        // One overlay: the js fence stays the code it is.
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertEqual(Self.overlays(in: contentView).count, 1)

        // Looking at the diagram changed nothing about the document.
        XCTAssertEqual(document.model.content, source)
        XCTAssertFalse(document.isDocumentEdited)

        // The caret entering the block puts the code back: the engine
        // withholds the block from its report, and the overlay comes down.
        let textView = try XCTUnwrap(EditorViewLocator.textView(in: window))
        let fenceBody = (textView.string as NSString).range(of: "A --> B")
        textView.setSelectedRange(NSRange(location: fenceBody.location, length: 0))
        let gone = Date().addingTimeInterval(10)
        while Date() < gone, Self.overlays(in: contentView).contains(where: { !$0.isHidden }) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(
            Self.overlays(in: contentView).contains { !$0.isHidden },
            "the overlay stayed up over the caret"
        )

        // And leaving it draws the diagram again.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let back = Date().addingTimeInterval(10)
        var redrawn = false
        while Date() < back, !redrawn {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            redrawn = Self.overlays(in: contentView).contains { !$0.isHidden && $0.image != nil }
        }
        XCTAssertTrue(redrawn, "the overlay did not come back after the caret left")
    }

    private static func overlays(in view: NSView) -> [DiagramOverlayView] {
        var found: [DiagramOverlayView] = []
        if let overlay = view as? DiagramOverlayView {
            found.append(overlay)
        }
        for subview in view.subviews {
            found.append(contentsOf: overlays(in: subview))
        }
        return found
    }
}
