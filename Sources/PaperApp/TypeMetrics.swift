import AppKit

/// Translations between the settings' units and the engine's.
///
/// PaperV2 stored the line width in CSS `ch` and the line height as a plain
/// multiple, and both survive here unchanged so a V2 settings file keeps its
/// meaning. The engine wants points, so these two convert.
enum TypeMetrics {
    /// The width of the text column for a measure in characters. A character
    /// is the width of the font's zero, the same ruler `ch` uses, so the
    /// column keeps its measure when the font changes.
    static func readingWidth(for font: NSFont, measure: Int) -> CGFloat {
        let zero = ("0" as NSString).size(withAttributes: [.font: font]).width
        return CGFloat(measure) * zero
    }

    /// Points the engine must add to the font's natural line height to reach
    /// `leading` times the type size. The engine's only seam raises the
    /// minimum line height above natural, so a leading below the face's own
    /// height clamps at natural instead of tightening past it.
    static func extraLineSpacing(for font: NSFont, leading: Double) -> CGFloat {
        // The same natural height the engine computes, ceil included.
        let natural = ceil(font.ascender - font.descender + font.leading)
        return max(0, CGFloat(leading) * font.pointSize - natural)
    }
}
