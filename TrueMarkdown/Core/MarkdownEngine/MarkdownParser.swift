import Foundation
@preconcurrency import Markdown

// MARK: - Public API

/// Parses a Markdown string into a swift-markdown Document AST.
struct MarkdownParser {
    /// Parse options enabling all common extensions.
    nonisolated(unsafe) private static let parseOptions: ParseOptions = [
        .parseBlockDirectives,
        .parseSymbolLinks
    ]

    /// Returns a parsed `Document` from the given Markdown string.
    static func parse(_ text: String) -> Document {
        Document(parsing: text, options: parseOptions)
    }
}
