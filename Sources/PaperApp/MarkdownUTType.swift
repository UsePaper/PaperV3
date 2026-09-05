import UniformTypeIdentifiers

extension UTType {
    /// The system identifier for Markdown. Declared in the bundled app's
    /// Info.plist under UTImportedTypeDeclarations; `importedAs` keeps the
    /// unbundled `swift run` binary working with the same identifier.
    static let markdownDocument = UTType(
        importedAs: "net.daringfireball.markdown",
        conformingTo: .plainText
    )
}
