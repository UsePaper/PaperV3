import AppKit
import Combine
import MarkdownEngine
import PaperCore

/// The mermaid diagrams of one window, drawn as images over their code
/// blocks. Ported from PaperV2's exception 6, under the same law: nothing
/// in the document moves. The overlay reads the fence text and draws in a
/// view of its own over the block, so looking at a diagram cannot change
/// the file, and the code block itself stays a styled run of text.
///
/// Geometry comes from the engine's own code block report, the one it
/// publishes for the copy-code button: it re-delivers on every scroll,
/// edit and layout change, and it withholds a block while the caret sits
/// inside it, which is what puts the code back for editing. The views are
/// subviews of the text view, so between deliveries they scroll with the
/// text instead of trailing it.
@MainActor
final class DiagramOverlayController {
    private let model: EditorModel
    private weak var window: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?

    /// The engine's latest word on where the visible code blocks sit.
    private var latestSelections: [CodeBlockSelection] = []
    /// One overlay per engine block id, alive while the block is.
    private var overlays: [Int: DiagramOverlayView] = [:]
    /// The view the overlays are installed in. A settings change rebuilds
    /// the editor, and the overlays must not survive into the wrong view.
    private weak var installedTextView: NSTextView?
    /// The editor state the engine was last nudged for. See primeReport.
    private var lastNudgeKey: String?

    init(model: EditorModel, window: NSWindow) {
        self.model = model
        self.window = window

        model.codeBlockSelections
            .sink { [weak self] selections in
                self?.latestSelections = selections
                self?.apply()
            }
            .store(in: &subscriptions)

        // Source mode shows the raw text, where a drawing has no place.
        model.$showsSource
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.apply() }
            .store(in: &subscriptions)

        // An edit can turn a fence into a diagram before it scrolls or the
        // caret moves, so the cache is warmed straight from the source. The
        // apply also covers a revert, which rebuilds the text without a
        // delivery of its own.
        model.$content
            .dropFirst()
            .sink { [weak self] content in
                self?.prerender(content)
                self?.apply()
            }
            .store(in: &subscriptions)

        // A diagram holds the colors it was drawn in, so the theme moving
        // has to draw it again. The effective appearance covers both the
        // settings row and the system flipping underneath "system".
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for overlay in self.overlays.values { overlay.image = nil }
                self.apply()
            }
        }
    }

    // MARK: Placement

    private func apply() {
        guard let window else { return }
        guard let textView = EditorViewLocator.textView(in: window),
              let scrollView = textView.enclosingScrollView,
              let documentView = scrollView.documentView
        else {
            removeAllOverlays()
            return
        }
        if textView !== installedTextView {
            removeAllOverlays()
            installedTextView = textView
        }
        if model.showsSource {
            removeAllOverlays()
            return
        }

        let palette = MermaidPalette.current()
        let diagrams = latestSelections.filter { MermaidFences.isDiagramLanguage($0.language) }
        if diagrams.isEmpty {
            primeReport(textView)
        }
        var seen = Set<Int>()

        for selection in diagrams {
            seen.insert(selection.id)
            // The engine reports in the visible area's space; the overlay
            // lives in the text view, so the scroll and the text view's own
            // offset go back on.
            let contentOffset = scrollView.contentView.bounds.origin
            let originInDocument = textView.convert(NSPoint.zero, to: documentView)
            let frame = NSRect(
                x: selection.rect.origin.x + contentOffset.x - originInDocument.x,
                y: selection.rect.origin.y + contentOffset.y - originInDocument.y,
                width: selection.rect.width,
                height: selection.rect.height
            )

            let overlay = overlays[selection.id] ?? {
                let view = DiagramOverlayView()
                textView.addSubview(view)
                overlays[selection.id] = view
                return view
            }()
            overlay.frame = frame
            overlay.pageColor = palette.pageColor
            overlay.surfaceColor = palette.surfaceColor
            let source = Self.normalize(selection.code)
            if overlay.source != source || overlay.image == nil {
                overlay.source = source
                overlay.image = nil
                MermaidRenderer.shared.render(
                    source: source,
                    palette: palette.palette
                ) { [weak overlay] image in
                    guard let overlay, overlay.source == source else { return }
                    // No image means mermaid could not read it: the overlay
                    // stays down and the code stands unchanged, which is
                    // the whole of the error interface.
                    overlay.image = image
                    overlay.isHidden = image == nil
                }
            }
            overlay.isHidden = overlay.image == nil
        }

        // A block the report no longer carries has been edited away, taken
        // by the caret, or scrolled out. On screen that must show the code
        // now; off screen the overlay keeps its place so scrolling back
        // does not flash the code first.
        for (id, overlay) in overlays where !seen.contains(id) {
            if overlay.frame.intersects(textView.visibleRect) {
                overlay.removeFromSuperview()
                overlays.removeValue(forKey: id)
            }
        }
    }

    /// The engine computes its code block report on edits and selection
    /// changes, not on the initial load, so a freshly opened document that
    /// is never clicked — reading mode's whole life — would keep its
    /// diagrams undrawn. Posting the selection notification runs the same
    /// pipeline a click would. Once per editor and document state: the key
    /// stops the nudge from feeding on the empty deliveries it causes when
    /// every fence is off screen.
    private func primeReport(_ textView: NSTextView) {
        guard !MermaidFences.fences(in: model.content).isEmpty else { return }
        let key = "\(ObjectIdentifier(textView).hashValue)|\(model.content.hashValue)"
        guard lastNudgeKey != key else { return }
        lastNudgeKey = key
        // Off the current call stack: this can run inside the engine's own
        // delivery, and the notification re-enters its selection handler.
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            NotificationCenter.default.post(
                name: NSTextView.didChangeSelectionNotification,
                object: textView
            )
        }
    }

    private func removeAllOverlays() {
        for overlay in overlays.values { overlay.removeFromSuperview() }
        overlays.removeAll()
    }

    /// Draws what the document holds into the cache before it is asked
    /// for, so a diagram scrolling into view appears drawn, not drawing.
    private func prerender(_ content: String) {
        let palette = MermaidPalette.current().palette
        for fence in MermaidFences.fences(in: content) {
            MermaidRenderer.shared.render(
                source: Self.normalize(fence.body),
                palette: palette
            ) { _ in }
        }
    }

    /// The engine hands the block's content with its final line end, the
    /// scanner without. One shape, so the two paths share a cache entry.
    private static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .newlines)
    }
}

/// The picture over one code block: the page color to blot out the code,
/// the block's own surface behind the drawing, and the drawing centered,
/// scaled down when the block is smaller than it, never up. Mouse events
/// pass through, so a click lands in the text below and puts the caret in
/// the block, which is what brings the code back.
final class DiagramOverlayView: NSView {
    var source: String = ""
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var pageColor: NSColor = .textBackgroundColor {
        didSet { needsDisplay = true }
    }
    var surfaceColor: NSColor = .textBackgroundColor {
        didSet { needsDisplay = true }
    }

    /// The block's inner margin, matching the room the engine leaves
    /// around code.
    private let padding: CGFloat = 12

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var isFlipped: Bool {
        // The text view is flipped; agreeing with it keeps the frames the
        // controller computes meaning what they say.
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Page first: the surface color can carry alpha, and the code
        // beneath must not shine through it.
        pageColor.setFill()
        bounds.fill()
        surfaceColor.setFill()
        bounds.fill()

        guard let image else { return }
        let room = bounds.insetBy(dx: padding, dy: padding)
        guard room.width > 0, room.height > 0 else { return }
        let scale = min(1, min(room.width / image.size.width, room.height / image.size.height))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let target = NSRect(
            x: room.midX - size.width / 2,
            y: room.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image.draw(
            in: target,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
    }
}
