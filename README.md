# PaperV3

Paper, native. A minimal WYSIWYG Markdown editor for macOS, built on AppKit
and TextKit 2. One window, one file, one editing pane. You type Markdown, the
syntax hides itself, and the formatted result stays in place. There is no
preview pane.

This is the successor to [PaperV2](https://github.com/UsePaper/PaperV2), the
Tauri version, rebuilt as a native application around
[swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine).
It is under construction and has not shipped a release yet.

## Running it

```bash
swift build          # compile
swift test           # the test suite, round trip corpus included
make app             # assemble a runnable build/Paper.app
```

Requires macOS 14 and Xcode 15 or newer.

## What is here so far

- The editor: live WYSIWYG styling over the raw Markdown, which the engine
  keeps as its text storage, so what is saved is what was typed.
- Two modes, stepped from a button in the title bar: **presentation** writes,
  **reading** puts the keyboard away and leaves the text selectable.
- The raw source, one toggle away.
- The settings sheet: theme, font, text size, line width, line height, status
  bar, opens in, spellcheck. Eight settings, two groups, and a Reset.
- Seven bundled writing faces, each under the SIL Open Font License.
- Find and replace through the system find bar.
- The outline panel, floating over the right edge: it lists the headings,
  navigates on a click, marks the section being read, and withdraws on its
  own when left alone.

The file watcher, the `paper` command line tool, Copy Markdown, the manual
update check and Mermaid diagrams are on the way; they exist in PaperV2 and
PaperV3 does not ship without them.

## Keys

| Key | Action |
|---|---|
| `⌘O` | Open a file |
| `⌘S` | Save |
| `⇧⌘S` | Save as |
| `⌘/` | Toggle the raw Markdown source |
| `⇧⌘P` / `⇧⌘R` | Presentation, reading |
| `⇧⌘O` | Toggle the outline |
| `⌘F` | Find |
| `⌘,` | Settings |

## How it holds together

The Markdown text on disk is the source of truth. The engine holds that text
verbatim and styles it with attributes only, so the round trip is exact:
`Tests/PaperTests` holds the same corpus as PaperV2, and every file in it must
come back byte for byte.

## Licence

MIT. See [LICENSE](LICENSE).

Bundled fonts keep their own licences, which sit beside them in
`Sources/PaperApp/Resources/Fonts/`. All of them are the SIL Open Font
License.
