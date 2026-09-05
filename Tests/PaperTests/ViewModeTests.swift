import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import PaperApp

/// The mode model, and the document plumbing around it, exercised headless.
final class ViewModeTests: XCTestCase {
    func testStartingModeFollowsThePreference() {
        XCTAssertEqual(ViewMode.starting(preference: .reading, blank: false), .reading)
        XCTAssertEqual(ViewMode.starting(preference: .presentation, blank: false), .presentation)
    }

    func testBlankDocumentNeverStartsInReading() {
        XCTAssertEqual(ViewMode.starting(preference: .reading, blank: true), .presentation)
        XCTAssertEqual(ViewMode.starting(preference: .presentation, blank: true), .presentation)
    }

    func testOtherFlipsBetweenTheTwoModes() {
        XCTAssertEqual(ViewMode.presentation.other, .reading)
        XCTAssertEqual(ViewMode.reading.other, .presentation)
    }
}

@MainActor
final class DocumentModeTests: XCTestCase {
    private let markdownType = UTType.markdownDocument.identifier

    func testNewDocumentStartsInPresentation() {
        let document = MarkdownDocument()
        XCTAssertEqual(document.startingMode(preferring: .presentation), .presentation)
    }

    func testWhitespaceOnlyFileIgnoresAReadingPreference() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("  \n\n".utf8), ofType: markdownType)
        XCTAssertEqual(document.startingMode(preferring: .reading), .presentation)
    }

    func testFileWithContentHonorsAReadingPreference() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("# Title\n".utf8), ofType: markdownType)
        XCTAssertEqual(document.startingMode(preferring: .reading), .reading)
    }

    /// The mode and the source toggle are views of the document, so neither
    /// may dirty it or change what a save would write.
    func testModeAndSourceToggleNeverDirtyTheDocument() throws {
        let original = Data("# Title\n\nBody\n".utf8)
        let document = MarkdownDocument()
        try document.read(from: original, ofType: markdownType)
        document.model.mode = .reading
        document.model.showsSource = true
        document.model.showsSource = false
        document.model.mode = .presentation
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(try document.data(ofType: markdownType), original)
    }

    func testMenuActionsMoveTheFocusedDocumentOnly() {
        let moved = MarkdownDocument()
        let bystander = MarkdownDocument()
        moved.showReading(nil)
        XCTAssertEqual(moved.model.mode, .reading)
        XCTAssertEqual(bystander.model.mode, .presentation)
        moved.showPresentation(nil)
        XCTAssertEqual(moved.model.mode, .presentation)
    }

    func testSourceToggleFlipsBothWays() {
        let document = MarkdownDocument()
        document.toggleMarkdownSource(nil)
        XCTAssertTrue(document.model.showsSource)
        document.toggleMarkdownSource(nil)
        XCTAssertFalse(document.model.showsSource)
    }

    func testValidationChecksTheCurrentModeAndTheSourceToggle() {
        let document = MarkdownDocument()
        document.showReading(nil)
        document.toggleMarkdownSource(nil)

        let reading = NSMenuItem(title: "Reading",
                                 action: #selector(MarkdownDocument.showReading(_:)),
                                 keyEquivalent: "")
        XCTAssertTrue(document.validateUserInterfaceItem(reading))
        XCTAssertEqual(reading.state, .on)

        let presentation = NSMenuItem(title: "Presentation",
                                      action: #selector(MarkdownDocument.showPresentation(_:)),
                                      keyEquivalent: "")
        XCTAssertTrue(document.validateUserInterfaceItem(presentation))
        XCTAssertEqual(presentation.state, .off)

        let source = NSMenuItem(title: "Markdown Source",
                                action: #selector(MarkdownDocument.toggleMarkdownSource(_:)),
                                keyEquivalent: "")
        XCTAssertTrue(document.validateUserInterfaceItem(source))
        XCTAssertEqual(source.state, .on)
    }
}
