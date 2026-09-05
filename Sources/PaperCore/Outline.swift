import Foundation

/// One heading of a document, in document order, for the outline panel.
public struct OutlineHeading: Equatable {
    /// 1 for `#` through 6 for `######`.
    public let level: Int
    /// The heading without its markers, trimmed. Empty for a bare `#`.
    public let text: String
    /// The whole heading line in the source, as a UTF-16 range without the
    /// line end, ready for NSTextView APIs.
    public let range: NSRange
    /// Where the heading text begins, in UTF-16 units, for placing a caret.
    public let textLocation: Int

    public init(level: Int, text: String, range: NSRange, textLocation: Int) {
        self.level = level
        self.text = text
        self.range = range
        self.textLocation = textLocation
    }
}

/// Reads the ATX headings out of Markdown source without parsing it fully.
///
/// Blockquote markers are stripped first, so `> # Title` counts, the way the
/// PaperV2 outline counted a heading wherever the document held one. Lines
/// inside fenced code blocks never count, wherever the fence sits. Setext
/// headings are not read: the serializer writes ATX only, so a document that
/// passes through the editor has none.
public enum Outline {
    public static func headings(in markdown: String) -> [OutlineHeading] {
        var headings: [OutlineHeading] = []
        var openFence: MarkdownLineScanner.Fence?

        for line in MarkdownLineScanner.lines(of: markdown as NSString) {
            let units = line.units
            let afterQuote = MarkdownLineScanner.quotePrefix(of: units).end

            if let fence = openFence {
                if MarkdownLineScanner.closesFence(units, from: afterQuote, fence: fence) {
                    openFence = nil
                }
                continue
            }
            if let fence = MarkdownLineScanner.opensFence(units, from: afterQuote) {
                openFence = fence
                continue
            }
            guard let heading = parseHeading(units, from: afterQuote) else { continue }

            headings.append(OutlineHeading(
                level: heading.level,
                text: heading.text,
                range: line.range,
                textLocation: line.range.location + heading.textOffset
            ))
        }
        return headings
    }

    // The line anatomy lives in MarkdownLineScanner, shared with the
    // mermaid fence finder so the two scanners read a line the same way.

    private typealias ASCII = MarkdownLineScanner.ASCII

    private static func parseHeading(
        _ units: [UInt16],
        from start: Int
    ) -> (level: Int, text: String, textOffset: Int)? {
        guard var index = MarkdownLineScanner.skipIndent(units, from: start) else { return nil }
        var level = 0
        while index < units.count, units[index] == ASCII.hash, level < 7 {
            index += 1
            level += 1
        }
        guard (1...6).contains(level) else { return nil }
        // The marker needs a space, a tab or the line end after it, or the
        // line is a paragraph like `#hashtag`.
        if index < units.count, units[index] != ASCII.space, units[index] != ASCII.tab {
            return nil
        }
        while index < units.count, units[index] == ASCII.space || units[index] == ASCII.tab {
            index += 1
        }
        let textStart = index

        var end = units.count
        while end > textStart, units[end - 1] == ASCII.space || units[end - 1] == ASCII.tab {
            end -= 1
        }
        // An optional closing run of hashes, its own or after a space.
        var beforeHashes = end
        while beforeHashes > textStart, units[beforeHashes - 1] == ASCII.hash {
            beforeHashes -= 1
        }
        if beforeHashes < end,
           beforeHashes == textStart
           || units[beforeHashes - 1] == ASCII.space
           || units[beforeHashes - 1] == ASCII.tab {
            end = beforeHashes
            while end > textStart, units[end - 1] == ASCII.space || units[end - 1] == ASCII.tab {
                end -= 1
            }
        }

        let text = String(decoding: units[textStart..<end], as: UTF16.self)
        return (level, text, textStart)
    }
}
