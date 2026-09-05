import Foundation

/// Line anatomy shared by the source scanners: the outline's heading reader
/// and the mermaid fence finder. On UTF-16 units so the offsets match
/// NSString, which is what NSTextView APIs speak.
enum MarkdownLineScanner {
    enum ASCII {
        static let space: UInt16 = 0x20
        static let tab: UInt16 = 0x09
        static let hash: UInt16 = 0x23
        static let greaterThan: UInt16 = 0x3E
        static let backtick: UInt16 = 0x60
        static let tilde: UInt16 = 0x7E
        static let lineFeed: UInt16 = 0x0A
        static let carriageReturn: UInt16 = 0x0D
    }

    struct Fence {
        let character: UInt16
        let length: Int
        /// Where the info string starts, right after the fence run.
        let infoStart: Int
    }

    /// One line of the source without its line end, plus where it sits.
    struct Line {
        let units: [UInt16]
        /// The line's range in the source, line end excluded.
        let range: NSRange
    }

    /// The lines of the text, walked in order.
    static func lines(of source: NSString) -> [Line] {
        var lines: [Line] = []
        var location = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(lineRange)
            var units = Array(source.substring(with: lineRange).utf16)
            while let last = units.last, last == ASCII.lineFeed || last == ASCII.carriageReturn {
                units.removeLast()
            }
            lines.append(Line(
                units: units,
                range: NSRange(location: lineRange.location, length: units.count)
            ))
        }
        return lines
    }

    /// The run of `>` markers opening a line, each allowed up to three
    /// leading spaces and one space after, the way CommonMark opens a
    /// blockquote. The limit caps how many markers are consumed, so a
    /// scanner can strip exactly the depth a construct opened at and no
    /// more.
    static func quotePrefix(of units: [UInt16], limit: Int = Int.max) -> (end: Int, depth: Int) {
        var index = 0
        var depth = 0
        while depth < limit {
            var probe = index
            var spaces = 0
            while probe < units.count, units[probe] == ASCII.space, spaces < 3 {
                probe += 1
                spaces += 1
            }
            guard probe < units.count, units[probe] == ASCII.greaterThan else { break }
            probe += 1
            if probe < units.count, units[probe] == ASCII.space {
                probe += 1
            }
            index = probe
            depth += 1
        }
        return (index, depth)
    }

    /// Up to three spaces of indent; a fourth makes indented code.
    static func skipIndent(_ units: [UInt16], from start: Int) -> Int? {
        var index = start
        var spaces = 0
        while index < units.count, units[index] == ASCII.space {
            index += 1
            spaces += 1
            if spaces > 3 { return nil }
        }
        return index
    }

    static func opensFence(_ units: [UInt16], from start: Int) -> Fence? {
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
        return Fence(character: character, length: length, infoStart: end)
    }

    static func closesFence(_ units: [UInt16], from start: Int, fence: Fence) -> Bool {
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
}
