import AppKit
import MarkdownEngine
import SwiftUI
import XCTest
@testable import PaperCore

/// The most important test in the repository. The Markdown file on disk is
/// the source of truth: loading it into the editor and serializing it back
/// must reproduce it byte for byte. A failing corpus file is a finding, not
/// a defect in the test — never delete or weaken a case to make it pass.
///
/// The engine has no separate document model: the text storage holds the
/// Markdown source itself (in display form), and styling is attributes only.
/// Loading goes through the public `NativeTextViewWrapper`, exactly as the
/// app does, and serializing reads the storage back through
/// `WikiLinkService.makeStorageState`, the engine's display-to-storage
/// inverse that its own edit pipeline uses before writing to the binding.
@MainActor
final class RoundTripTests: XCTestCase {
    func testCorpusRoundTripsByteForByte() throws {
        let corpus = try corpusFiles()
        XCTAssertGreaterThan(corpus.count, 50, "The corpus did not copy into the test bundle")

        var failures: [String] = []
        for url in corpus {
            let name = url.lastPathComponent
            let originalData = try Data(contentsOf: url)
            let text = try MarkdownText.decode(originalData)

            let serialized = serializeThroughEditor(text.content)

            let roundTripped = MarkdownText(content: serialized, lineEnding: text.lineEnding)
            if roundTripped.encode() != originalData {
                failures.append(name)
                reportDivergence(name: name, expected: text.content, actual: serialized)
            } else {
                print("PASS \(name)")
            }
        }

        if !failures.isEmpty {
            XCTFail("Corpus files that do not round-trip (\(failures.count)/\(corpus.count)): \(failures.joined(separator: ", "))")
        }
    }

    /// Guards the round trip against passing vacuously: if the wrapper never
    /// initialized, the storage would hold the text unstyled (or not at all)
    /// and equality above would mean nothing. A heading styled larger than
    /// the body proves the engine's pipeline ran on what we loaded.
    func testEditorStylesWhatItLoads() {
        var observedFontSize: CGFloat = 0
        let source = "# Heading\n\nBody text.\n"
        _ = serializeThroughEditor(source) { textView in
            // Index 2 is the H of "Heading": past the `# ` marker, which the
            // styler hides by shrinking it to a near-zero font.
            let index = (source as NSString).range(of: "Heading").location
            if let font = textView.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont {
                observedFontSize = font.pointSize
            }
        }
        XCTAssertGreaterThan(observedFontSize, 16, "The heading kept the body font, so the engine never styled the document")
    }

    // MARK: - Editor round trip

    /// Load `content` into the real editor stack and read it back.
    private func serializeThroughEditor(
        _ content: String,
        inspect: ((NSTextView) -> Void)? = nil
    ) -> String {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 1000),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        // close() would release the window a second time under ARC and
        // crash the autorelease pool drain at test teardown.
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = NativeTextViewWrapper(text: .constant(content))
        let hosting = NSHostingView(rootView: editor)
        hosting.frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        guard let textView = Self.findTextView(in: hosting) else {
            XCTFail("The wrapper did not produce an NSTextView")
            return ""
        }
        inspect?(textView)
        let display = textView.string
        return WikiLinkService.makeStorageState(
            from: display,
            existingMetadata: [:],
            textStorage: textView.textStorage
        ).storage
    }

    private static func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let found = findTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - Reporting

    private func corpusFiles() throws -> [URL] {
        guard let corpusURL = Bundle.module.url(forResource: "corpus", withExtension: nil) else {
            XCTFail("Corpus directory missing from the test bundle")
            return []
        }
        return try FileManager.default
            .contentsOfDirectory(at: corpusURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Print the first differing line so a failure names what the engine rewrote.
    private func reportDivergence(name: String, expected: String, actual: String) {
        let expectedLines = expected.components(separatedBy: "\n")
        let actualLines = actual.components(separatedBy: "\n")
        for index in 0..<max(expectedLines.count, actualLines.count) {
            let want = index < expectedLines.count ? expectedLines[index] : "<missing line>"
            let got = index < actualLines.count ? actualLines[index] : "<missing line>"
            if want != got {
                print("FAIL \(name) at line \(index + 1)")
                print("  disk:   \(want.debugDescription)")
                print("  editor: \(got.debugDescription)")
                return
            }
        }
        print("FAIL \(name): same lines, different bytes (line endings or trailing content)")
    }
}
