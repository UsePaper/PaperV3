import XCTest
@testable import PaperCore

/// The heading extraction the outline panel is built from. It must read a
/// heading wherever the document holds one, and never inside a code fence.
final class OutlineTests: XCTestCase {
    private func headings(_ markdown: String) -> [(Int, String)] {
        Outline.headings(in: markdown).map { ($0.level, $0.text) }
    }

    func testReadsAllSixLevelsInOrder() {
        let source = """
        # One
        ## Two
        ### Three
        #### Four
        ##### Five
        ###### Six
        """
        let result = Outline.headings(in: source)
        XCTAssertEqual(result.map(\.level), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(result.map(\.text), ["One", "Two", "Three", "Four", "Five", "Six"])
    }

    func testSevenHashesAreAParagraph() {
        XCTAssertTrue(headings("####### Too deep").isEmpty)
    }

    func testAHashWithoutASpaceIsAParagraph() {
        XCTAssertTrue(headings("#hashtag").isEmpty)
    }

    func testEmptyHeadingsKeepTheirPlace() {
        let result = Outline.headings(in: "#\n\n## \n")
        XCTAssertEqual(result.map(\.level), [1, 2])
        XCTAssertEqual(result.map(\.text), ["", ""])
    }

    func testClosingHashesAreStripped() {
        XCTAssertEqual(headings("## Title ##").map(\.1), ["Title"])
        XCTAssertEqual(headings("# Title#").map(\.1), ["Title#"])
    }

    func testUpToThreeSpacesOfIndentAreAllowed() {
        XCTAssertEqual(headings("   # Indented").count, 1)
        XCTAssertTrue(headings("    # Code").isEmpty)
    }

    func testHeadingsInsideBlockquotesCount() {
        let source = """
        > # Quoted
        > > ## Nested
        """
        let result = Outline.headings(in: source)
        XCTAssertEqual(result.map(\.level), [1, 2])
        XCTAssertEqual(result.map(\.text), ["Quoted", "Nested"])
    }

    func testHeadingsInsideFencesNeverCount() {
        let source = """
        # Before

        ```md
        # Inside
        ```

        ~~~
        ## Also inside
        ~~~

        # After
        """
        XCTAssertEqual(headings(source).map(\.1), ["Before", "After"])
    }

    func testAnUnclosedFenceSwallowsTheRest() {
        let source = """
        # Before
        ```
        # Inside forever
        """
        XCTAssertEqual(headings(source).map(\.1), ["Before"])
    }

    func testAFenceInsideABlockquoteStillFences() {
        let source = """
        > ```
        > # Inside
        > ```
        > # After
        """
        XCTAssertEqual(headings(source).map(\.1), ["After"])
    }

    func testAShorterRunDoesNotCloseAFence() {
        let source = """
        ````
        ```
        # Still inside
        ````
        # Out
        """
        XCTAssertEqual(headings(source).map(\.1), ["Out"])
    }

    func testRangesPointAtTheHeadingLines() {
        let source = "Intro.\n\n## Two\n\nBody.\n"
        let result = Outline.headings(in: source)
        XCTAssertEqual(result.count, 1)
        let entry = result[0]
        let ns = source as NSString
        XCTAssertEqual(ns.substring(with: entry.range), "## Two")
        XCTAssertEqual(ns.substring(from: entry.textLocation).prefix(3), "Two")
    }

    func testTextLocationSitsAfterTheMarkers() {
        let entry = Outline.headings(in: "> ###   Spaced")[0]
        let ns = "> ###   Spaced" as NSString
        XCTAssertEqual(ns.substring(from: entry.textLocation), "Spaced")
    }

    func testOffsetsAreUTF16() {
        let source = "Émoji 🙂 first.\n\n# Héading\n"
        let entry = Outline.headings(in: source)[0]
        XCTAssertEqual((source as NSString).substring(with: entry.range), "# Héading")
    }
}
