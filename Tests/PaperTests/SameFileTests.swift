import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import PaperApp

/// One document per file, whatever the path is called. Finder says
/// /private/tmp/a.md where a shell says /tmp/a.md, and they are the same
/// document. NSDocumentController's lookup is what openDocument uses to
/// raise an existing window instead of opening a second copy, so the lookup
/// is what these tests hold to account.
@MainActor
final class SameFileTests: XCTestCase {
    private let markdownType = UTType.markdownDocument.identifier

    private var controller: NSDocumentController {
        // The first controller instantiated becomes the shared one. In this
        // test process that may already have happened, and either controller
        // class answers document(for:) the same way.
        NSDocumentController.shared
    }

    private func makeOpenDocument(atTmpPath path: String) throws -> NSDocument {
        try Data("alias test\n".utf8).write(to: URL(fileURLWithPath: path))
        let document = try MarkdownDocument(
            contentsOf: URL(fileURLWithPath: path),
            ofType: markdownType
        )
        controller.addDocument(document)
        return document
    }

    func testTmpAliasFindsTheOpenDocument() throws {
        let path = "/tmp/paper-samefile-\(UUID().uuidString).md"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let document = try makeOpenDocument(atTmpPath: path)
        defer { controller.removeDocument(document) }

        let viaPrivate = controller.document(for: URL(fileURLWithPath: "/private" + path))
        XCTAssertIdentical(viaPrivate, document)
    }

    func testPrivateAliasFindsTheOpenDocument() throws {
        let name = "paper-samefile-\(UUID().uuidString).md"
        let path = "/private/tmp/" + name
        defer { try? FileManager.default.removeItem(atPath: path) }
        let document = try makeOpenDocument(atTmpPath: path)
        defer { controller.removeDocument(document) }

        let viaTmp = controller.document(for: URL(fileURLWithPath: "/tmp/" + name))
        XCTAssertIdentical(viaTmp, document)
    }
}
