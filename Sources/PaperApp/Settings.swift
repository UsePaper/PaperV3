import Foundation

/// The stored theme choice. `system` means no explicit choice, so the
/// application follows the system appearance.
enum Theme: String, CaseIterable {
    case system
    case light
    case dark
}

/// A bundled body font on offer. The `id` is the stored value and matches
/// PaperV2's ids, so a settings file written by the old application still
/// picks the same face here.
struct FontChoice: Identifiable, Equatable {
    let id: String
    let label: String
    /// The PostScript name of the regular face. The family name is not used
    /// for lookup, because two of the bundled families register under
    /// surprising family names and one of those resolves to its bold face.
    let postScriptName: String
}

/// The settings model, and the single place that knows its shape. Exactly
/// eight settings, the same eight as PaperV2. A ninth needs a reason.
struct Settings: Equatable {
    var theme: Theme
    /// An id from `bodyFonts`, not a font name.
    var font: String
    /// The editor text size in points.
    var fontSize: Int
    /// How wide the text column runs, in characters (the width of a zero).
    var measure: Int
    /// The line height, as a multiple of the type size.
    var leading: Double
    var spellcheck: Bool
    var statusbar: Bool
    /// The mode a new window opens in. Windows already open are left alone.
    var defaultMode: ViewMode

    // MARK: The choices on offer

    static let bodyFonts: [FontChoice] = [
        FontChoice(id: "literata", label: "Literata", postScriptName: "Literata-Regular"),
        FontChoice(id: "lora", label: "Lora", postScriptName: "Lora-Regular"),
        FontChoice(id: "newsreader", label: "Newsreader", postScriptName: "Newsreader16pt16pt-Regular"),
        FontChoice(id: "source-serif", label: "Source Serif", postScriptName: "SourceSerif4-Regular"),
        FontChoice(id: "inter", label: "Inter", postScriptName: "Inter-Regular"),
        FontChoice(id: "quattro", label: "iA Quattro", postScriptName: "iAWriterQuattroS-Regular"),
        FontChoice(id: "mono", label: "JetBrains Mono", postScriptName: "JetBrainsMono-Regular"),
    ]

    static let fontSizeRange = 13...24

    /// Named widths, not a number: nobody picks 62 characters by eye. The
    /// stored value stays a number so an old file still parses.
    struct MeasurePreset: Equatable {
        let id: String
        let label: String
        let chars: Int
    }

    static let measurePresets: [MeasurePreset] = [
        MeasurePreset(id: "narrow", label: "Narrow", chars: 58),
        MeasurePreset(id: "medium", label: "Medium", chars: 70),
        MeasurePreset(id: "wide", label: "Wide", chars: 84),
    ]

    // The clamp has to clear the widest preset, or parsing would quietly
    // squash it and two of the three settings would come out the same width.
    static let measureRange = 40...120

    /// Named for the same reason as the widths: nobody wants to choose 1.62.
    struct LeadingPreset: Equatable {
        let id: String
        let label: String
        let height: Double
    }

    static let leadingPresets: [LeadingPreset] = [
        LeadingPreset(id: "tight", label: "Tight", height: 1.45),
        LeadingPreset(id: "normal", label: "Normal", height: 1.7),
        LeadingPreset(id: "relaxed", label: "Relaxed", height: 2.0),
    ]

    static let leadingRange = 1.2...2.4

    /// PaperV2 defaulted the font to the system face, which is not one of the
    /// seven bundled here, so the first serif stands in for it.
    static let `default` = Settings(
        theme: .system,
        font: "literata",
        fontSize: 17,
        measure: 70,
        leading: 1.7,
        spellcheck: true,
        statusbar: true,
        defaultMode: .presentation
    )

    var fontChoice: FontChoice {
        Self.bodyFonts.first { $0.id == font } ?? Self.bodyFonts[0]
    }

    /// The named width closest to the stored number.
    var measurePreset: MeasurePreset {
        Self.measurePresets.min { abs($0.chars - measure) < abs($1.chars - measure) }
            ?? Self.measurePresets[0]
    }

    /// The named line height closest to the stored number.
    var leadingPreset: LeadingPreset {
        Self.leadingPresets.min { abs($0.height - leading) < abs($1.height - leading) }
            ?? Self.leadingPresets[0]
    }

    /// The same rules the file reader applies, for values arriving from the
    /// user interface instead of from disk.
    mutating func clamp() {
        if !Self.bodyFonts.contains(where: { $0.id == font }) {
            font = Self.default.font
        }
        fontSize = fontSize.clamped(to: Self.fontSizeRange)
        measure = measure.clamped(to: Self.measureRange)
        leading = min(max(leading, Self.leadingRange.lowerBound), Self.leadingRange.upperBound)
    }

    // MARK: Parsing

    /// Rebuilds a settings object from whatever was on disk. Anything
    /// missing, mistyped or out of range falls back to its default, so an
    /// old or hand edited file can never leave the application unusable.
    static func parse(_ data: Data?) -> Settings {
        guard let data,
              let raw = try? JSONSerialization.jsonObject(with: data),
              let object = raw as? [String: Any] else {
            return .default
        }
        return parse(object)
    }

    static func parse(_ object: [String: Any]) -> Settings {
        var settings = Settings.default

        if let value = object["theme"] as? String, let theme = Theme(rawValue: value) {
            settings.theme = theme
        }
        if let value = object["font"] as? String, bodyFonts.contains(where: { $0.id == value }) {
            settings.font = value
        }
        if let value = number(object["fontSize"]) {
            settings.fontSize = Int(value.rounded()).clamped(to: fontSizeRange)
        }
        if let value = number(object["measure"]) {
            settings.measure = Int(value.rounded()).clamped(to: measureRange)
        }
        if let value = number(object["leading"]) {
            settings.leading = min(max(value, leadingRange.lowerBound), leadingRange.upperBound)
        }
        if let value = bool(object["spellcheck"]) {
            settings.spellcheck = value
        }
        if let value = bool(object["statusbar"]) {
            settings.statusbar = value
        }
        if let value = object["defaultMode"] as? String, let mode = mode(named: value) {
            settings.defaultMode = mode
        }

        return settings
    }

    /// Pretty and key-sorted, so the file on disk stays readable and diffs
    /// stay small when one setting changes.
    func encode() -> Data {
        let object: [String: Any] = [
            "theme": theme.rawValue,
            "font": font,
            "fontSize": fontSize,
            "measure": measure,
            "leading": leading,
            "spellcheck": spellcheck,
            "statusbar": statusbar,
            "defaultMode": Self.name(of: defaultMode),
        ]
        // The object holds only plain JSON types, so serialization cannot throw.
        return (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()
    }

    static func name(of mode: ViewMode) -> String {
        switch mode {
        case .presentation: "presentation"
        case .reading: "reading"
        }
    }

    private static func mode(named value: String) -> ViewMode? {
        switch value {
        case "presentation": .presentation
        case "reading": .reading
        // PaperV2 had a third mode. Its typing mode maps to ours, so a file
        // it wrote keeps meaning "open ready to type".
        case "editing": .presentation
        default: nil
        }
    }

    /// JSONSerialization hands numbers and booleans back as NSNumber both
    /// ways, and Swift happily bridges `1` to `true`. These two keep a
    /// number from passing as a boolean and the other way around.
    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, !isBoolean(value) else { return nil }
        return value.doubleValue
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, isBoolean(value) else { return nil }
        return value.boolValue
    }

    private static func isBoolean(_ value: NSNumber) -> Bool {
        CFGetTypeID(value) == CFBooleanGetTypeID()
    }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
