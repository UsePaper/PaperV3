import XCTest
@testable import PaperCore

/// The mermaid fence finder: what counts as a diagram, and where it sits.
/// The ranges are UTF-16 offsets into the source, the same offsets the
/// text view speaks, because that is where the overlay has to land.
final class MermaidFenceTests: XCTestCase {
    // MARK: The language rule

    func testTheFirstWordNamesTheDiagram() {
        XCTAssertTrue(MermaidFences.isDiagramLanguage("mermaid"))
        XCTAssertTrue(MermaidFences.isDiagramLanguage("Mermaid"))
        XCTAssertTrue(MermaidFences.isDiagramLanguage(" mermaid something"))
        XCTAssertFalse(MermaidFences.isDiagramLanguage("mermaidish"))
        XCTAssertFalse(MermaidFences.isDiagramLanguage("js"))
        XCTAssertFalse(MermaidFences.isDiagramLanguage(""))
        XCTAssertFalse(MermaidFences.isDiagramLanguage(nil))
    }

    // MARK: Finding fences

    func testFindsAFenceWhereItSits() throws {
        let source = "Prose before.\n\n```mermaid\ngraph TD\n  A --> B\n```\n\nProse after.\n"
        let fences = MermaidFences.fences(in: source)

        XCTAssertEqual(fences.count, 1)
        let fence = try XCTUnwrap(fences.first)
        XCTAssertEqual(fence.body, "graph TD\n  A --> B")

        let expected = (source as NSString).range(of: "```mermaid\ngraph TD\n  A --> B\n```")
        XCTAssertEqual(fence.range, expected)
    }

    func testIgnoresOtherFences() {
        let source = "```js\nconst x = 1;\n```\n\n```mermaid\ngraph TD\n```\n"
        let fences = MermaidFences.fences(in: source)
        XCTAssertEqual(fences.count, 1)
        XCTAssertEqual(fences.first?.body, "graph TD")
    }

    func testAMermaidLineInsideAnotherFenceIsContent() {
        // The outer fence owns everything until it closes, so the mermaid
        // opener inside it never opens anything.
        let source = "````md\n```mermaid\ngraph TD\n```\n````\n"
        XCTAssertTrue(MermaidFences.fences(in: source).isEmpty)
    }

    func testFindsSeveralInDocumentOrder() {
        let source = "```mermaid\nfirst\n```\n\ntext\n\n```mermaid\nsecond\n```\n"
        let fences = MermaidFences.fences(in: source)
        XCTAssertEqual(fences.map(\.body), ["first", "second"])
        XCTAssertLessThan(fences[0].range.location, fences[1].range.location)
    }

    func testAnUnclosedFenceRunsToTheEnd() throws {
        // The normal state while a diagram is being typed. CommonMark closes
        // the fence at the end of the document, and so does the scanner.
        let source = "before\n\n```mermaid\ngraph TD\n  A --> B"
        let fences = MermaidFences.fences(in: source)
        XCTAssertEqual(fences.count, 1)
        let fence = try XCTUnwrap(fences.first)
        XCTAssertEqual(fence.body, "graph TD\n  A --> B")
        XCTAssertEqual(NSMaxRange(fence.range), (source as NSString).length)
    }

    func testAQuotedFenceCountsWithItsMarkersStripped() {
        let source = "> ```mermaid\n> graph TD\n> ```\n"
        let fences = MermaidFences.fences(in: source)
        XCTAssertEqual(fences.count, 1)
        XCTAssertEqual(fences.first?.body, "graph TD")
    }

    func testAnUnquotedFenceKeepsAQuoteLookingBodyLine() {
        // Only the depth the fence opened at is stripped. A body line that
        // happens to start with `>` is diagram source, not a quote marker.
        let source = "```mermaid\n> not a quote\n```\n"
        XCTAssertEqual(MermaidFences.fences(in: source).first?.body, "> not a quote")
    }

    func testTildeFencesCount() {
        let source = "~~~mermaid\ngraph TD\n~~~\n"
        XCTAssertEqual(MermaidFences.fences(in: source).first?.body, "graph TD")
    }

    func testTheCorpusFileYieldsItsOneDiagram() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "mermaid-fence",
            withExtension: "md",
            subdirectory: "corpus"
        ))
        let text = try MarkdownText.decode(Data(contentsOf: url))
        let fences = MermaidFences.fences(in: text.content)
        XCTAssertEqual(fences.count, 1)
        XCTAssertEqual(
            fences.first?.body,
            "graph TD\n  A[Start] --> B{Decision}\n  B -->|Yes| C[Finish]\n  B -->|No| D[Alternate]"
        )
    }
}
