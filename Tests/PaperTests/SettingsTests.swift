import XCTest
@testable import PaperApp
@testable import PaperCore

/// The defensive settings parsing: a corrupt or partial file falls back
/// field by field, never as a whole.
final class SettingsTests: XCTestCase {
    func testDefaults() {
        let settings = Settings.default
        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.font, "literata")
        XCTAssertEqual(settings.fontSize, 17)
        XCTAssertEqual(settings.measure, 70)
        XCTAssertEqual(settings.leading, 1.7)
        XCTAssertTrue(settings.spellcheck)
        XCTAssertTrue(settings.statusbar)
        XCTAssertEqual(settings.defaultMode, .presentation)
    }

    func testMissingFileFallsBackToDefaults() {
        XCTAssertEqual(Settings.parse(nil), .default)
    }

    func testGarbageFallsBackToDefaults() {
        XCTAssertEqual(Settings.parse(Data("not json at all".utf8)), .default)
        XCTAssertEqual(Settings.parse(Data("[1, 2, 3]".utf8)), .default)
        XCTAssertEqual(Settings.parse(Data("\"a string\"".utf8)), .default)
    }

    func testPartialFileKeepsWhatItHas() {
        let settings = Settings.parse(Data(#"{"fontSize": 20, "theme": "dark"}"#.utf8))
        XCTAssertEqual(settings.fontSize, 20)
        XCTAssertEqual(settings.theme, .dark)
        XCTAssertEqual(settings.font, Settings.default.font)
        XCTAssertEqual(settings.measure, Settings.default.measure)
    }

    func testEachBadFieldFallsBackAlone() {
        let settings = Settings.parse(Data(
            #"{"theme": "sepia", "font": "comic-sans", "fontSize": "big", "measure": 64, "spellcheck": 1, "defaultMode": "focus"}"#
                .utf8
        ))
        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.font, "literata")
        XCTAssertEqual(settings.fontSize, 17)
        XCTAssertEqual(settings.measure, 64)
        // A number is not a boolean, so 1 does not pass as true.
        XCTAssertTrue(settings.spellcheck)
        XCTAssertEqual(settings.defaultMode, .presentation)
    }

    func testBooleanIsNotANumber() {
        let settings = Settings.parse(Data(#"{"fontSize": true, "statusbar": false}"#.utf8))
        XCTAssertEqual(settings.fontSize, 17)
        XCTAssertFalse(settings.statusbar)
    }

    func testOutOfRangeValuesClamp() {
        let settings = Settings.parse(Data(
            #"{"fontSize": 99, "measure": 10, "leading": 9.5}"#.utf8
        ))
        XCTAssertEqual(settings.fontSize, 24)
        XCTAssertEqual(settings.measure, 40)
        XCTAssertEqual(settings.leading, 2.4)

        let low = Settings.parse(Data(#"{"fontSize": 2, "measure": 500, "leading": 0.1}"#.utf8))
        XCTAssertEqual(low.fontSize, 13)
        XCTAssertEqual(low.measure, 120)
        XCTAssertEqual(low.leading, 1.2)
    }

    func testFractionalSizesRound() {
        let settings = Settings.parse(Data(#"{"fontSize": 17.6, "measure": 69.5}"#.utf8))
        XCTAssertEqual(settings.fontSize, 18)
        XCTAssertEqual(settings.measure, 70)
    }

    func testEveryOfferedFontParses() {
        for choice in Settings.bodyFonts {
            let settings = Settings.parse(Data(#"{"font": "\#(choice.id)"}"#.utf8))
            XCTAssertEqual(settings.font, choice.id)
            XCTAssertEqual(settings.fontChoice, choice)
        }
    }

    func testPaperV2EditingModeMapsToPresentation() {
        let settings = Settings.parse(Data(#"{"defaultMode": "editing"}"#.utf8))
        XCTAssertEqual(settings.defaultMode, .presentation)
    }

    func testReadingModeParses() {
        let settings = Settings.parse(Data(#"{"defaultMode": "reading"}"#.utf8))
        XCTAssertEqual(settings.defaultMode, .reading)
    }

    func testEncodeParseRoundTrip() {
        var settings = Settings.default
        settings.theme = .dark
        settings.font = "mono"
        settings.fontSize = 21
        settings.measure = 84
        settings.leading = 1.45
        settings.spellcheck = false
        settings.statusbar = false
        settings.defaultMode = .reading
        XCTAssertEqual(Settings.parse(settings.encode()), settings)
    }

    func testClosestPresetIsNamed() {
        var settings = Settings.default
        settings.measure = 60
        XCTAssertEqual(settings.measurePreset.id, "narrow")
        settings.leading = 1.9
        XCTAssertEqual(settings.leadingPreset.id, "relaxed")
    }
}

/// The store: clamping on update, and the opens-in preference feeding the
/// starting mode of new documents.
@MainActor
final class SettingsStoreTests: XCTestCase {
    private var previousShared: SettingsStore?

    override func setUp() {
        super.setUp()
        previousShared = SettingsStore.shared
        SettingsStore.shared = SettingsStore(fileURL: nil)
    }

    override func tearDown() {
        if let previousShared {
            SettingsStore.shared = previousShared
        }
        super.tearDown()
    }

    func testUpdateClamps() {
        let store = SettingsStore(fileURL: nil)
        store.update { $0.fontSize = 99 }
        XCTAssertEqual(store.settings.fontSize, 24)
        store.update { $0.font = "papyrus" }
        XCTAssertEqual(store.settings.font, "literata")
    }

    func testResetRestoresEveryDefault() {
        let store = SettingsStore(fileURL: nil)
        store.update {
            $0.theme = .dark
            $0.fontSize = 22
            $0.statusbar = false
        }
        store.reset()
        XCTAssertEqual(store.settings, .default)
    }

    func testStoreRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paper-settings-tests-\(UUID().uuidString)")
            .appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = SettingsStore(fileURL: url)
        store.update {
            $0.theme = .light
            $0.defaultMode = .reading
        }
        store.saveNow()

        let reloaded = SettingsStore(fileURL: url)
        XCTAssertEqual(reloaded.settings, store.settings)
    }

    func testOpensInFeedsTheStartingMode() {
        SettingsStore.shared.update { $0.defaultMode = .reading }
        XCTAssertEqual(MarkdownDocument.startingModePreference, .reading)

        // The blank rule still wins over the preference.
        let document = MarkdownDocument()
        XCTAssertEqual(
            document.startingMode(preferring: MarkdownDocument.startingModePreference),
            .presentation
        )

        SettingsStore.shared.update { $0.defaultMode = .presentation }
        XCTAssertEqual(MarkdownDocument.startingModePreference, .presentation)
    }
}

/// The status bar's word count.
final class WordCountTests: XCTestCase {
    func testEmptyAndWhitespace() {
        XCTAssertEqual(WordCount.count(""), 0)
        XCTAssertEqual(WordCount.count("  \n\t\n"), 0)
    }

    func testPlainProse() {
        XCTAssertEqual(WordCount.count("Hello world"), 2)
        XCTAssertEqual(WordCount.count("One two three four five."), 5)
    }

    func testMarkersDoNotCount() {
        XCTAssertEqual(WordCount.count("# Title\n\n- one\n- two\n\n---\n"), 3)
    }

    func testApostrophesStayOneWord() {
        XCTAssertEqual(WordCount.count("don't stop"), 2)
    }
}
