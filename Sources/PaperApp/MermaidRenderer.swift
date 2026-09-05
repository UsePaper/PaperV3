import AppKit
import WebKit

/// Draws mermaid sources to images, one at a time, in an offscreen web view
/// running the vendored mermaid.min.js. The web view never joins a document
/// window and loads nothing but bundle files, so drawing a diagram cannot
/// change a document and cannot reach the network.
///
/// Everything is asynchronous and cached: a source that has been drawn in
/// the current palette answers immediately, and a source mermaid cannot
/// read answers nil, which the overlay treats as "leave the code alone".
@MainActor
final class MermaidRenderer: NSObject, WKNavigationDelegate {
    static let shared = MermaidRenderer()

    /// Everything the drawing depends on besides the source. Part of the
    /// cache key, so a theme or font change draws anew instead of serving
    /// the colors of the appearance that was.
    struct Palette: Equatable, Hashable {
        var themeVariables: [String: String]
        /// The opaque ground the snapshot keeps, as a CSS color. The
        /// overlay paints the same color behind the image.
        var background: String
        var fontFamily: String
        var fontFaceCSS: String
    }

    /// Drawn at twice the requested size and displayed at half, so the
    /// snapshot is crisp on a Retina screen wherever the window sits.
    private static let scale: CGFloat = 2
    /// The viewport diagrams are measured against before the page is sized
    /// to the drawing. Wide enough that nothing wraps for lack of room.
    private static let measuringSize = NSSize(width: 1600, height: 1200)

    private struct Request {
        let key: CacheKey
        let source: String
        let palette: Palette
        var completions: [(NSImage?) -> Void]
    }

    private struct CacheKey: Hashable {
        let source: String
        let palette: Palette
    }

    private var webView: WKWebView?
    /// Never shown. It exists because a web view with no window at all is
    /// not reliably painted, and a snapshot of it can come back empty.
    private var hiddenWindow: NSWindow?
    private var isPageReady = false
    private var pending: [Request] = []
    private var isDrawing = false
    /// nil is a remembered failure: a source that does not parse will not
    /// parse on the next scroll tick either.
    private var cache: [CacheKey: NSImage?] = [:]

    /// Draws a source in a palette and calls back on the main queue, now
    /// when the cache answers, later when the web view has to.
    func render(
        source: String,
        palette: Palette,
        completion: @escaping (NSImage?) -> Void
    ) {
        let key = CacheKey(source: source, palette: palette)
        if let cached = cache[key] {
            completion(cached)
            return
        }
        if let index = pending.firstIndex(where: { $0.key == key }) {
            pending[index].completions.append(completion)
            return
        }
        pending.append(Request(key: key, source: source, palette: palette, completions: [completion]))
        ensureWebView()
        drawNext()
    }

    // MARK: The web view

    private func ensureWebView() {
        guard webView == nil else { return }
        guard let page = Bundle.module.url(
            forResource: "mermaid",
            withExtension: "html",
            subdirectory: "Mermaid"
        ), let resources = Bundle.module.resourceURL else {
            failEverything()
            return
        }

        let configuration = WKWebViewConfiguration()
        let view = WKWebView(
            frame: NSRect(origin: .zero, size: Self.measuringSize),
            configuration: configuration
        )
        view.navigationDelegate = self
        // Access to the whole resource directory, so the page can reach the
        // bundled fonts beside it. Nothing outside the bundle is readable.
        view.loadFileURL(page, allowingReadAccessTo: resources)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.measuringSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        self.hiddenWindow = window
        self.webView = view
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageReady = true
        drawNext()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failEverything()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        failEverything()
    }

    /// The page itself would not load. Nothing will ever draw, so every
    /// caller hears nil and the code stays visible, which is the failure
    /// mode the feature promises.
    private func failEverything() {
        let requests = pending
        pending = []
        for request in requests {
            cache[request.key] = NSImage?.none
            for completion in request.completions { completion(nil) }
        }
    }

    // MARK: Drawing

    private func drawNext() {
        guard isPageReady, !isDrawing, !pending.isEmpty, let webView else { return }
        isDrawing = true
        let request = pending.removeFirst()

        // Measured against a roomy viewport first, then sized to the answer.
        webView.pageZoom = Self.scale
        webView.frame = NSRect(origin: .zero, size: Self.measuringSize)

        let arguments: [String: Any] = [
            "source": request.source,
            "options": [
                "themeVariables": request.palette.themeVariables,
                "background": request.palette.background,
                "fontFamily": request.palette.fontFamily,
                "fontFaceCSS": request.palette.fontFaceCSS,
            ],
        ]
        webView.callAsyncJavaScript(
            "return await draw(source, options);",
            arguments: arguments,
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                guard let size = Self.size(from: value) else {
                    self.finish(request, with: nil)
                    return
                }
                self.snapshot(request, size: size)
            case .failure:
                // A diagram mermaid cannot read. Not an error worth
                // interrupting anyone over.
                self.finish(request, with: nil)
            }
        }
    }

    private static func size(from value: Any?) -> NSSize? {
        guard let object = value as? [String: Any],
              let width = (object["width"] as? NSNumber)?.doubleValue,
              let height = (object["height"] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return nil }
        return NSSize(width: width, height: height)
    }

    private func snapshot(_ request: Request, size: NSSize) {
        guard let webView else {
            finish(request, with: nil)
            return
        }
        webView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: size.width * Self.scale, height: size.height * Self.scale)
        )
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.afterScreenUpdates = true
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            if let image {
                // The bitmap holds the doubled drawing; the size in points
                // stays the natural one, which is what makes it Retina.
                image.size = size
            }
            self?.finish(request, with: image)
        }
    }

    private func finish(_ request: Request, with image: NSImage?) {
        // Failures are remembered alongside successes, or every scroll tick
        // would re-run a parse that is known to fail.
        if cache.count > 64 {
            cache.removeAll(keepingCapacity: true)
        }
        cache[request.key] = image
        for completion in request.completions { completion(image) }
        isDrawing = false
        drawNext()
    }
}
