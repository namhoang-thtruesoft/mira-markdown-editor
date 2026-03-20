import Foundation
import Markdown

// MARK: - TOC Entry

struct TOCEntry: Identifiable, Sendable {
    let id = UUID()
    let level: Int          // 1 = H1, 2 = H2, …
    let title: String
    let blockId: String     // Maps to data-block-id in preview
    let lineNumber: Int     // 1-indexed source line (for editor scroll)
}

// MARK: - TOC Extractor

enum TOCExtractor {
    /// Walks the Document AST and returns heading entries.
    static func extract(from document: Document) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        var blockIndex = 0
        for child in document.children {
            if let heading = child as? Heading {
                entries.append(TOCEntry(
                    level: heading.level,
                    title: heading.plainText,
                    blockId: "block-\(blockIndex)",
                    lineNumber: heading.range?.lowerBound.line ?? 1
                ))
            }
            blockIndex += 1
        }
        return entries
    }
}
