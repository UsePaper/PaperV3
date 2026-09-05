import Foundation

/// A Markdown file's text, decoded for editing and encoded for saving.
///
/// The file on disk is the source of truth. Decoding strips a UTF-8 BOM and
/// normalizes CRLF to LF, because the editor works on LF text. Encoding puts
/// the original line-ending style back, so a file the user never touched is
/// written byte for byte as it was read.
public struct MarkdownText: Equatable, Sendable {
    public enum LineEnding: Equatable, Sendable {
        case lf
        case crlf
    }

    /// The text with LF line endings, no BOM.
    public var content: String
    /// The line-ending style the file had on disk.
    public let lineEnding: LineEnding

    public init(content: String, lineEnding: LineEnding = .lf) {
        self.content = content
        self.lineEnding = lineEnding
    }

    public enum DecodingError: Error {
        case notUTF8
    }

    public static func decode(_ data: Data) throws -> MarkdownText {
        var data = data
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.count >= 3, data.prefix(3).elementsEqual(bom) {
            data.removeFirst(3)
        }
        guard let raw = String(data: data, encoding: .utf8) else {
            throw DecodingError.notUTF8
        }
        let lineEnding: LineEnding = raw.contains("\r\n") ? .crlf : .lf
        let content = raw.replacingOccurrences(of: "\r\n", with: "\n")
        return MarkdownText(content: content, lineEnding: lineEnding)
    }

    public func encode() -> Data {
        let text: String
        switch lineEnding {
        case .lf:
            text = content
        case .crlf:
            text = content.replacingOccurrences(of: "\n", with: "\r\n")
        }
        return Data(text.utf8)
    }
}
