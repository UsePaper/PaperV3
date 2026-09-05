import Foundation

/// Words in a document, counted from the raw Markdown. Word enumeration is
/// used rather than a whitespace split so a `#`, a list dash or a code fence
/// does not count as a word the reader never wrote.
public enum WordCount {
    public static func count(_ text: String) -> Int {
        var words = 0
        text.enumerateSubstrings(
            in: text.startIndex...,
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in
            words += 1
        }
        return words
    }
}
