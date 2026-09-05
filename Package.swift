// swift-tools-version: 5.9
import PackageDescription

// Paper — a minimal WYSIWYG Markdown editor for macOS.
// The product is called Paper. The repository is PaperV3.
//
// PaperCore holds the pure text model (encoding, line-ending preservation)
// and PaperApp the whole application; the executable is one call into
// PaperApp. Tests link the two libraries, because SPM test targets link
// against libraries more reliably than against executables.
let package = Package(
    name: "PaperV3",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/nodes-app/swift-markdown-engine", from: "0.9.0")
    ],
    targets: [
        .target(name: "PaperCore"),
        .target(
            name: "PaperApp",
            dependencies: [
                "PaperCore",
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
                .product(name: "MarkdownEngineCodeBlocks", package: "swift-markdown-engine"),
            ]
        ),
        .executableTarget(
            name: "Paper",
            dependencies: ["PaperApp"]
        ),
        .testTarget(
            name: "PaperTests",
            dependencies: [
                "PaperCore",
                "PaperApp",
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
            ],
            resources: [
                .copy("Resources/corpus")
            ]
        ),
    ]
)
