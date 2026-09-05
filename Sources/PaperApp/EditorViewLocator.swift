import AppKit

/// Finds the engine's text view inside a window. The engine builds its
/// editor as an NSScrollView around a single NSTextView and hands out no
/// reference to either, so the one sanctioned route is to walk the view tree
/// from the window's content view. The editor body is the only NSTextView
/// in the window, which is what makes the walk safe; a find bar's field
/// editor is the one other NSTextView that can appear, and it is skipped by
/// its flag.
enum EditorViewLocator {
    static func textView(in window: NSWindow) -> NSTextView? {
        window.contentView.flatMap(firstTextView(under:))
    }

    private static func firstTextView(under view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, !textView.isFieldEditor {
            return textView
        }
        for subview in view.subviews {
            if let found = firstTextView(under: subview) {
                return found
            }
        }
        return nil
    }
}
