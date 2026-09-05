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
        let source = markdown as NSString
        var headings: [OutlineHeading] = []
        var openFence: Fence?
        var location = 0

        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(lineRange)

            var units = Array(source.substring(with: lineRange).utf16)
            while let last = units.last, last == ASCII.lineFeed || last == ASCII.carriageReturn {
                units.removeLast()
            }

            let afterQuote = quotePrefixEnd(of: units)

            if let fence = openFence {
                if closesFence(units, from: afterQuote, fence: fence) {
                    openFence = nil
                }
                continue
            }
            if let fence = opensFence(units, from: afterQuote) {
                openFence = fence
                continue
            }
            guard let heading = parseHeading(units, from: afterQuote) else { continue }

            headings.append(OutlineHeading(
                level: heading.level,
                text: heading.text,
                range: NSRange(location: lineRange.location, length: units.count),
                textLocation: lineRange.location + heading.textOffset
            ))
        }
        return headings
    }

    // MARK: Line anatomy, on UTF-16 units so the offsets match NSString

    private enum ASCII {
        static let space: UInt16 = 0x20
        static let tab: UInt16 = 0x09
        static let hash: UInt16 = 0x23
        static let greaterThan: UInt16 = 0x3E
        static let backtick: UInt16 = 0x60
        static let tilde: UInt16 = 0x7E
        static let lineFeed: UInt16 = 0x0A
        static let carriageReturn: UInt16 = 0x0D
    }

    private struct Fence {
        let character: UInt16
        let length: Int
    }

    /// The end of any run of `>` markers, each allowed up to three leading
    /// spaces and one space after, the way CommonMark opens a blockquote.
    private static func quotePrefixEnd(of units: [UInt16]) -> Int {
        var index = 0
        while true {
            var probe = index
            var spaces = 0
            while probe < units.count, units[probe] == ASCII.space, spaces < 3 {
                probe += 1
                spaces += 1
            }
            guard probe < units.count, units[probe] == ASCII.greaterThan else { return index }
            probe += 1
            if probe < units.count, units[probe] == ASCII.space {
                probe += 1
            }
            index = probe
        }
    }

    /// Up to three spaces of indent; a fourth makes indented code.
    private static func skipIndent(_ units: [UInt16], from start: Int) -> Int? {
        var index = start
        var spaces = 0
        while index < units.count, units[index] == ASCII.space {
            index += 1
            spaces += 1
            if spaces > 3 { return nil }
        }
        return index
    }

    private static func opensFence(_ units: [UInt16], from start: Int) -> Fence? {
        guard let index = skipIndent(units, from: start) else { return nil }
        guard index < units.count else { return nil }
        let character = units[index]
        guard character == ASCII.backtick || character == ASCII.tilde else { return nil }
        var end = index
        while end < units.count, units[end] == character { end += 1 }
        let length = end - index
        guard length >= 3 else { return nil }
        // A backtick fence cannot carry a backtick in its info string.
        if character == ASCII.backtick, units[end...].contains(ASCII.backtick) { return nil }
        return Fence(character: character, length: length)
    }

    private static func closesFence(_ units: [UInt16], from start: Int, fence: Fence) -> Bool {
        guard let index = skipIndent(units, from: start) else { return false }
        var end = index
        while end < units.count, units[end] == fence.character { end += 1 }
        guard end - index >= fence.length else { return false }
        while end < units.count {
            guard units[end] == ASCII.space || units[end] == ASCII.tab else { return false }
            end += 1
        }
        return true
    }

    private static func parseHeading(
        _ units: [UInt16],
        from start: Int
    ) -> (level: Int, text: String, textOffset: Int)? {
        guard var index = skipIndent(units, from: start) else { return nil }
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
