import Foundation

/// When the outline panel puts itself away. The decisions are pure so the
/// rules can be tested without a window: the caller schedules a close after
/// the returned delay, or cancels the running one on nil.
///
/// The rules are PaperV2's. Left alone the panel withdraws after five
/// seconds, and a pointer over it holds it open. A click on an entry lights
/// the shorter three-second fuse, and that one burns under the pointer too:
/// the click was the arrival. Any later activity puts the ordinary rule
/// back.
struct OutlineFuse {
    /// Left alone this long, the panel withdraws.
    static let idleDelay: TimeInterval = 5
    /// A click got the reader where they were going; the panel leaves sooner.
    static let clickedDelay: TimeInterval = 3

    private(set) var isHovered = false

    enum Event {
        case opened
        case entryClicked
        /// Scrolling, or the document changing under the panel.
        case activity
        case hoverBegan
        case hoverEnded
    }

    /// The delay before the panel should close after this event. Nil cancels
    /// any running countdown, which is how hovering holds the panel open.
    mutating func delay(after event: Event) -> TimeInterval? {
        switch event {
        case .opened, .activity:
            return isHovered ? nil : Self.idleDelay
        case .entryClicked:
            return Self.clickedDelay
        case .hoverBegan:
            isHovered = true
            return nil
        case .hoverEnded:
            isHovered = false
            return Self.idleDelay
        }
    }
}
