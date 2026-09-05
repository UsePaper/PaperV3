import Foundation

/// One ```mermaid fence in a document, for the diagram overlay.
///
/// The fence stays an ordinary code block in the document and on disk: this
/// scanner only reads, so looking at a diagram cannot change the file.
public struct MermaidFence: Equatable {
    /// The whole fence in the source, from the start of the opening line to
    /// the end of the closing line, as a UTF-16 range without the trailing
    /// line end. An unclosed fence runs to the end of the text, the way
    /// CommonMark closes it at the end of the document.
    public let range: NSRange
    /// The diagram source between the fence lines, LF joined, with the
    /// blockquote markers of a quoted fence stripped the way a Markdown
    /// parser strips them from code content.
    public let body: String

    public init(range: NSRange, body: String) {
        self.range = range
        self.body = body
    }
}

/// Finds the mermaid fences without parsing the document fully. Same source
/// scanning family as Outline: line anatomy from MarkdownLineScanner, so a
/// fence reads the same to both.
public enum MermaidFences {
    /// Whether a fence's info string names a diagram: the first word,
    /// case-insensitively, the same rule PaperV2 applied.
    public static func isDiagramLanguage(_ language: String?) -> Bool {
        guard let language else { return false }
        let first = language
            .trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .first
        return first?.lowercased() == "mermaid"
    }

    public static func fences(in markdown: String) -> [MermaidFence] {
        var fences: [MermaidFence] = []
        var open: OpenFence?

        for line in MarkdownLineScanner.lines(of: markdown as NSString) {
            let units = line.units

            if var fence = open {
                // Only the depth the fence opened at is stripped: a `>` that
                // starts a body line of an unquoted fence is content.
                let afterQuote = MarkdownLineScanner.quotePrefix(
                    of: units,
                    limit: fence.quoteDepth
                ).end
                if MarkdownLineScanner.closesFence(units, from: afterQuote, fence: fence.fence) {
                    if fence.isDiagram {
                        fences.append(fence.closed(at: line.range))
                    }
                    open = nil
                } else {
                    fence.bodyLines.append(text(of: units, from: afterQuote))
                    fence.lastLineRange = line.range
                    open = fence
                }
                continue
            }

            let prefix = MarkdownLineScanner.quotePrefix(of: units)
            guard let fence = MarkdownLineScanner.opensFence(units, from: prefix.end) else {
                continue
            }
            let info = text(of: units, from: fence.infoStart)
            open = OpenFence(
                fence: fence,
                quoteDepth: prefix.depth,
                isDiagram: isDiagramLanguage(info),
                openingLineRange: line.range,
                lastLineRange: line.range,
                bodyLines: []
            )
        }

        // The document ended inside the fence, which is the normal state
        // while one is being typed. It still counts: CommonMark closes it
        // here, and a half-written diagram simply fails to draw.
        if let fence = open, fence.isDiagram {
            fences.append(fence.closed(at: fence.lastLineRange))
        }
        return fences
    }

    private struct OpenFence {
        let fence: MarkdownLineScanner.Fence
        let quoteDepth: Int
        let isDiagram: Bool
        let openingLineRange: NSRange
        var lastLineRange: NSRange
        var bodyLines: [String]

        func closed(at lastLine: NSRange) -> MermaidFence {
            MermaidFence(
                range: NSRange(
                    location: openingLineRange.location,
                    length: NSMaxRange(lastLine) - openingLineRange.location
                ),
                body: bodyLines.joined(separator: "\n")
            )
        }
    }

    private static func text(of units: [UInt16], from start: Int) -> String {
        String(decoding: units[start...], as: UTF16.self)
    }
}
