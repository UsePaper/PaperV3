import AppKit
import Combine
import PaperCore
import SwiftUI

/// The outline panel of one window: a floating card over the right edge
/// that lists the headings and navigates. It floats so opening it never
/// reflows the text, it reads the document without ever writing it, and it
/// withdraws on its own when left alone. Ported from PaperV2's outline.
///
/// `model.isOutlineVisible` is the one source of truth: the menu item, the
/// title bar button and the withdrawal timer all move that flag, and this
/// controller answers it.
final class OutlinePanelController: NSObject {
    private static let panelWidth: CGFloat = 220
    private static let trailingInset: CGFloat = 14
    private static let topInset: CGFloat = 8
    /// A heading past this line into the page counts as the section read.
    private static let activeBand: CGFloat = 100
    /// Scroll events are ignored this long after a click, so the scroll the
    /// click causes cannot take the mark off the entry that was clicked.
    private static let clickHold: TimeInterval = 0.2

    private let model: EditorModel
    private weak var window: NSWindow?
    private let state = OutlinePanelState()
    private var host: NSHostingView<OutlinePanelView>?
    private var fuse = OutlineFuse()
    private var withdrawTimer: Timer?
    private var scrollObserver: (any NSObjectProtocol)?
    private var holdUntil = Date.distantPast
    private var subscriptions = Set<AnyCancellable>()

    init(model: EditorModel, window: NSWindow) {
        self.model = model
        self.window = window
        super.init()

        model.$isOutlineVisible
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] visible in
                visible ? self?.show() : self?.hide()
            }
            .store(in: &subscriptions)

        // Source mode shows the raw text, which the outline cannot point
        // into, so it takes the panel with it.
        model.$showsSource
            .filter { $0 }
            .sink { [weak self] _ in self?.model.isOutlineVisible = false }
            .store(in: &subscriptions)

        // Typing is activity; the panel stays while the document moves, and
        // the list stays honest.
        model.$content
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.model.isOutlineVisible else { return }
                self.refresh()
                self.applyFuse(after: .activity)
            }
            .store(in: &subscriptions)
    }

    deinit {
        withdrawTimer?.invalidate()
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
    }

    // MARK: Showing and hiding

    private func show() {
        guard let contentView = window?.contentView else { return }
        let host = ensureHost(in: contentView)
        refresh()
        observeScrolling()

        host.isHidden = false
        place(host, open: false)
        animateSlide {
            host.animator().setFrameOrigin(self.origin(open: true, for: host))
        }

        fuse = OutlineFuse()
        applyFuse(after: .opened)
    }

    private func hide() {
        withdrawTimer?.invalidate()
        withdrawTimer = nil
        stopObservingScrolling()
        guard let host, !host.isHidden else { return }
        animateSlide {
            host.animator().setFrameOrigin(self.origin(open: false, for: host))
        } completion: { [weak self] in
            guard let self, !self.model.isOutlineVisible else { return }
            self.host?.isHidden = true
        }
    }

    private func ensureHost(in contentView: NSView) -> NSHostingView<OutlinePanelView> {
        if let host { return host }
        let view = OutlinePanelView(
            state: state,
            onSelect: { [weak self] index in self?.select(index) },
            onHoverChange: { [weak self] hovering in
                guard let self, self.model.isOutlineVisible else { return }
                self.applyFuse(after: hovering ? .hoverBegan : .hoverEnded)
            }
        )
        let host = NSHostingView(rootView: view)
        // Anchored to the top right corner through resizes; the size is
        // managed here, not by the mask.
        host.autoresizingMask = [.minXMargin, .minYMargin]
        host.isHidden = true
        contentView.addSubview(host)
        self.host = host
        return host
    }

    /// Sizes the card to its content, up to the room between the title bar
    /// and the status bar, and parks it on screen or just past the edge.
    private func place(_ host: NSHostingView<OutlinePanelView>, open: Bool) {
        guard let contentView = window?.contentView else { return }
        let bounds = contentView.bounds
        let statusBar: CGFloat = SettingsStore.shared.settings.statusbar ? 24 : 0
        let available = bounds.height - Self.topInset * 2 - statusBar
        let natural = host.fittingSize.height
        let height = min(natural, max(available, 0))
        host.setFrameSize(NSSize(width: Self.panelWidth, height: height))
        host.setFrameOrigin(origin(open: open, for: host))
    }

    private func origin(open: Bool, for host: NSView) -> NSPoint {
        guard let contentView = window?.contentView else { return .zero }
        let bounds = contentView.bounds
        let x = open
            ? bounds.maxX - Self.trailingInset - Self.panelWidth
            : bounds.maxX
        return NSPoint(x: x, y: bounds.maxY - Self.topInset - host.frame.height)
    }

    private func animateSlide(_ changes: @escaping () -> Void, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration =
                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            changes()
        }, completionHandler: completion)
    }

    // MARK: The list

    /// Rebuilds the entries from what the text view shows, or from the model
    /// while no text view is reachable. The text view's own string is the
    /// one the ranges must match, because that is the string the clicks
    /// scroll and the caret lands in.
    private func refresh() {
        let source = textView?.string ?? model.content
        let entries = Outline.headings(in: source)
        if entries != state.entries {
            state.entries = entries
            // The card grows and shrinks with its content; re-measure once
            // SwiftUI has taken the new entries.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.model.isOutlineVisible, let host = self.host else { return }
                self.place(host, open: true)
            }
        }
        markActive()
    }

    private var textView: NSTextView? {
        window.flatMap(EditorViewLocator.textView(in:))
    }

    // MARK: Navigation

    private func select(_ index: Int) {
        guard let textView else { return }
        // Read again at click time: edits move a heading, and the panel may
        // not have heard of them yet.
        let entries = Outline.headings(in: textView.string)
        guard entries.indices.contains(index) else { return }
        let entry = entries[index]
        state.entries = entries

        reveal(entry, in: textView)

        // The clicked entry is marked directly, and the scroll the click
        // causes is ignored: a centred reveal can leave the heading below
        // the band, where the scan would mark an earlier one.
        state.activeIndex = index
        holdUntil = Date().addingTimeInterval(Self.clickHold)
        applyFuse(after: .entryClicked)
    }

    /// Scrolls a heading to the centre and, where there is a caret, puts it
    /// there too. Reading mode scrolls without selecting: a click in the
    /// outline is navigation, not a selection.
    private func reveal(_ entry: OutlineHeading, in textView: NSTextView) {
        if model.mode == .presentation {
            textView.setSelectedRange(NSRange(location: entry.textLocation, length: 0))
            window?.makeFirstResponder(textView)
        }
        // Forces layout at the heading, so the fragment below has a frame.
        textView.scrollRangeToVisible(entry.range)
        guard let scrollView = textView.enclosingScrollView,
              let documentView = scrollView.documentView,
              let fragmentFrame = fragmentFrame(at: entry.range.location, in: textView)
        else { return }

        let frameInDocument = textView.convert(fragmentFrame, to: documentView)
        let clip = scrollView.contentView
        let lowest = -scrollView.contentInsets.top
        let highest = max(
            lowest,
            documentView.frame.height + scrollView.contentInsets.bottom - clip.bounds.height
        )
        let centred = frameInDocument.midY - clip.bounds.height / 2
        let target = min(max(centred, lowest), highest)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: target))
        scrollView.reflectScrolledClipView(clip)
    }

    /// The layout frame of the line starting at a UTF-16 offset, in the
    /// text view's coordinates. TextKit 2 only; the engine's view is one.
    private func fragmentFrame(at location: Int, in textView: NSTextView) -> CGRect? {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let textLocation = contentManager.location(
                  contentManager.documentRange.location,
                  offsetBy: location
              ),
              let fragment = layoutManager.textLayoutFragment(for: textLocation)
        else { return nil }
        return fragment.layoutFragmentFrame.offsetBy(
            dx: textView.textContainerOrigin.x,
            dy: textView.textContainerOrigin.y
        )
    }

    // MARK: Tracking the reader

    private func observeScrolling() {
        stopObservingScrolling()
        guard let clip = textView?.enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clip,
            queue: .main
        ) { [weak self] _ in self?.scrolled() }
    }

    private func stopObservingScrolling() {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        scrollObserver = nil
    }

    private func scrolled() {
        guard model.isOutlineVisible else { return }
        // During the hold the scroll is the click's own, and must not
        // stretch the click's shorter fuse back out to the idle one.
        guard Date() >= holdUntil else { return }
        markActive()
        applyFuse(after: .activity)
    }

    /// The last heading already past the top of the page is the section
    /// being read. Found by asking layout what sits a band below the top,
    /// then comparing source offsets, which spares laying out the document.
    private func markActive() {
        guard let textView,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else {
            state.activeIndex = nil
            return
        }
        let probe = CGPoint(
            x: 0,
            y: textView.visibleRect.minY + Self.activeBand - textView.textContainerOrigin.y
        )
        guard let fragment = layoutManager.textLayoutFragment(for: probe) else {
            state.activeIndex = nil
            return
        }
        let topOffset = contentManager.offset(
            from: contentManager.documentRange.location,
            to: fragment.rangeInElement.location
        )
        var active: Int?
        for (index, entry) in state.entries.enumerated() where entry.range.location <= topOffset {
            active = index
        }
        state.activeIndex = active
    }

    // MARK: Withdrawal

    private func applyFuse(after event: OutlineFuse.Event) {
        withdrawTimer?.invalidate()
        withdrawTimer = nil
        guard let delay = fuse.delay(after: event) else { return }
        withdrawTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) {
            [weak self] _ in
            self?.model.isOutlineVisible = false
        }
    }
}
