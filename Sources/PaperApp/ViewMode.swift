/// How a window shows its document. Two modes where PaperV2 had three:
/// the engine already styles the source live under the caret, so a separate
/// editing mode with visible markers has nothing left to show, and
/// presentation is the typing mode.
enum ViewMode: Hashable {
    /// The typing mode: live styling, keyboard active.
    case presentation
    /// The keyboard put away: no caret, nothing editable, the text still
    /// selectable so it can be quoted.
    case reading

    /// The mode the title bar button moves to.
    var other: ViewMode {
        self == .presentation ? .reading : .presentation
    }

    /// What the mode is called in the menu and on the button.
    var label: String {
        switch self {
        case .presentation: "Presentation"
        case .reading: "Reading"
        }
    }

    /// Reading has no caret and nothing to type into, so a document with
    /// nothing in it offers nothing to read and no way to begin. Only that
    /// case overrides the preference. No preference is stored yet; the
    /// parameter is where the settings value will arrive.
    static func starting(preference: ViewMode, blank: Bool) -> ViewMode {
        blank && preference == .reading ? .presentation : preference
    }
}
