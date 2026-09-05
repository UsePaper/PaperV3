import AppKit
import XCTest
@testable import PaperApp

/// The offscreen web view, end to end: a readable diagram becomes a real
/// image, and an unreadable one answers nil rather than an error.
@MainActor
final class MermaidRendererTests: XCTestCase {
    func testRendersASimpleGraph() {
        let expectation = expectation(description: "diagram drawn")
        var result: NSImage?
        let palette = MermaidRenderer.Palette(
            themeVariables: ["textColor": "rgb(20, 20, 20)"],
            background: "rgb(250, 250, 250)",
            fontFamily: "",
            fontFaceCSS: ""
        )
        MermaidRenderer.shared.render(source: "graph TD\n  A[Start] --> B[End]", palette: palette) { image in
            result = image
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 30)
        let image = result
        XCTAssertNotNil(image, "no image came back")
        if let image {
            print("PROBE image size: \(image.size)")
            XCTAssertGreaterThan(image.size.width, 20)
            XCTAssertGreaterThan(image.size.height, 20)
            // Not blank: some pixel differs from the ground.
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                var distinct = Set<Int>()
                for x in stride(from: 0, to: rep.pixelsWide, by: max(1, rep.pixelsWide / 40)) {
                    for y in stride(from: 0, to: rep.pixelsHigh, by: max(1, rep.pixelsHigh / 40)) {
                        if let color = rep.colorAt(x: x, y: y) {
                            distinct.insert(Int(color.redComponent * 255) << 16
                                | Int(color.greenComponent * 255) << 8
                                | Int(color.blueComponent * 255))
                        }
                    }
                }
                print("PROBE distinct sampled colors: \(distinct.count)")
                XCTAssertGreaterThan(distinct.count, 1, "the snapshot is a flat color")
            }
        }

        // A second render of a broken diagram answers nil.
        let second = self.expectation(description: "broken diagram refused")
        MermaidRenderer.shared.render(source: "graph TD\n  A[unclosed", palette: palette) { image in
            XCTAssertNil(image)
            second.fulfill()
        }
        wait(for: [second], timeout: 30)
    }
}
