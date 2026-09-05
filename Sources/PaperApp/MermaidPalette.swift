import AppKit

/// The page's own palette, handed to mermaid so a diagram follows the theme
/// and the font that are set instead of wearing mermaid's stock colors.
/// Ported from PaperV2: the `base` theme is the one that takes variables,
/// and the variables are read from the same colors the editor draws with,
/// so a diagram cannot drift from the rest of the page.
@MainActor
enum MermaidPalette {
    struct Current {
        /// What the renderer needs, and the cache key.
        let palette: MermaidRenderer.Palette
        /// What the overlay view paints behind the drawing.
        let pageColor: NSColor
        let surfaceColor: NSColor
    }

    static func current() -> Current {
        let settings = SettingsStore.shared.settings

        // Resolved under the application's appearance, because these are
        // dynamic colors and the web page they go to has no appearance.
        var text = NSColor.textColor
        var muted = NSColor.secondaryLabelColor
        var border = NSColor.separatorColor
        var page = NSColor.textBackgroundColor
        var surface = EditorScreen.services.syntaxHighlighter.backgroundColor()
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            text = resolve(text)
            muted = resolve(muted)
            border = resolve(border)
            page = resolve(page)
            surface = resolve(surface)
        }

        let fontFamily = "PaperBody"
        let variables: [String: String] = [
            // The block behind it is already a surface; a second one would
            // box the picture.
            "background": "transparent",
            "fontFamily": "\(fontFamily), serif",
            "fontSize": "14px",

            "primaryColor": css(surface),
            "primaryTextColor": css(text),
            "primaryBorderColor": css(border),
            "secondaryColor": css(page),
            "secondaryTextColor": css(text),
            "secondaryBorderColor": css(border),
            "tertiaryColor": css(page),
            "tertiaryTextColor": css(text),
            "tertiaryBorderColor": css(border),

            "mainBkg": css(surface),
            "nodeBorder": css(border),
            "nodeTextColor": css(text),
            "textColor": css(text),
            "lineColor": css(muted),

            "clusterBkg": css(page),
            "clusterBorder": css(border),
            // Without this an edge label wears a white box, which in the
            // dark theme is a torch shining out of the diagram.
            "edgeLabelBackground": css(page),
            "titleColor": css(text),
        ]

        return Current(
            palette: MermaidRenderer.Palette(
                themeVariables: variables,
                background: css(composite(surface, over: page)),
                fontFamily: fontFamily,
                fontFaceCSS: fontFace(for: settings.fontChoice, as: fontFamily)
            ),
            pageColor: page,
            surfaceColor: surface
        )
    }

    /// The color the block actually shows: the translucent surface laid
    /// over the page. The snapshot keeps it as its ground, and the overlay
    /// paints the same pair, so the two meet without a seam.
    private static func composite(_ top: NSColor, over bottom: NSColor) -> NSColor {
        let top = resolve(top)
        let bottom = resolve(bottom)
        let alpha = top.alphaComponent
        func mix(_ over: CGFloat, _ under: CGFloat) -> CGFloat {
            over * alpha + under * (1 - alpha)
        }
        return NSColor(
            srgbRed: mix(top.redComponent, bottom.redComponent),
            green: mix(top.greenComponent, bottom.greenComponent),
            blue: mix(top.blueComponent, bottom.blueComponent),
            alpha: 1
        )
    }

    /// The labels in the writing face the page uses. The web view is its
    /// own process, where the fonts this application registered do not
    /// exist, so the face travels as an @font-face rule pointing back into
    /// the bundle, beside the page that loads it.
    private static func fontFace(for choice: FontChoice, as family: String) -> String {
        let files: [String: String] = [
            "literata": "literata.woff2",
            "lora": "lora.woff2",
            "newsreader": "newsreader.woff2",
            "source-serif": "source-serif.woff2",
            "inter": "inter.woff2",
            "quattro": "ia-quattro.woff2",
            "mono": "jetbrains-mono.woff2",
        ]
        guard let file = files[choice.id] else { return "" }
        return "@font-face { font-family: \"\(family)\"; "
            + "src: url(\"../Fonts/\(file)\") format(\"woff2\"); }"
    }

    private static func resolve(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.sRGB) ?? color
    }

    /// A CSS color the web page reads the way AppKit meant it, alpha and
    /// all: the syntax highlighter's block background is translucent.
    private static func css(_ color: NSColor) -> String {
        let resolved = resolve(color)
        let red = Int((resolved.redComponent * 255).rounded())
        let green = Int((resolved.greenComponent * 255).rounded())
        let blue = Int((resolved.blueComponent * 255).rounded())
        let alpha = (resolved.alphaComponent * 1000).rounded() / 1000
        return "rgba(\(red), \(green), \(blue), \(alpha))"
    }
}
