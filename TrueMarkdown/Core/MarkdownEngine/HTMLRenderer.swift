import Foundation
@preconcurrency import Markdown

// MARK: - Block Patch

/// A patch representing a changed block to update in the WKWebView.
struct BlockPatch: Sendable {
    let blockId: String
    let html: String
}

// MARK: - HTML Renderer

/// Walks a swift-markdown AST and produces HTML fragments.
/// Each top-level block gets a stable `data-block-id` for incremental patching.
struct HTMLRenderer: MarkupVisitor {
    typealias Result = String

    private var blockIndex = 0
    /// When set, relative image paths are resolved against this directory.
    var baseDirectory: URL? = nil

    // MARK: - Entry Point

    /// Renders a full `Document` to an HTML string with block IDs.
    static func render(_ document: Document, baseDirectory: URL? = nil) -> String {
        var renderer = HTMLRenderer()
        renderer.baseDirectory = baseDirectory
        return renderer.visit(document)
    }

    /// Renders individual top-level blocks, each wrapped in a `<div data-block-id>` for
    /// incremental patching via `updateBlock()` in the WKWebView.
    static func renderBlocks(_ document: Document, baseDirectory: URL? = nil) -> [BlockPatch] {
        var renderer = HTMLRenderer()
        renderer.baseDirectory = baseDirectory
        return document.children.enumerated().map { (index, child) in
            let blockId = "block-\(index)"
            let inner = renderer.visit(child)
            let html = "<div data-block-id=\"\(blockId)\">\(inner)</div>"
            return BlockPatch(blockId: blockId, html: html)
        }
    }

    /// Full-page render with block ID wrappers — used for `setFullContent` on initial load.
    static func renderWithBlockIDs(_ document: Document, baseDirectory: URL? = nil) -> String {
        renderBlocks(document, baseDirectory: baseDirectory).map(\.html).joined(separator: "\n")
    }

    // MARK: - Visitor Methods

    mutating func defaultVisit(_ markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitDocument(_ document: Document) -> Result {
        document.children.map { visit($0) }.joined(separator: "\n")
    }

    mutating func visitHeading(_ heading: Heading) -> Result {
        let level = heading.level
        let id = heading.plainText.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let inner = heading.children.map { visit($0) }.joined()
        return "<h\(level) id=\"\(id)\">\(inner)</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> Result {
        let inner = paragraph.children.map { visit($0) }.joined()
        return "<p>\(inner)</p>\n"
    }

    mutating func visitText(_ text: Text) -> Result {
        escapeHTML(text.string)
    }

    mutating func visitStrong(_ strongText: Strong) -> Result {
        "<strong>\(strongText.children.map { visit($0) }.joined())</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> Result {
        "<em>\(emphasis.children.map { visit($0) }.joined())</em>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> Result {
        let rawCode = inlineCode.code
        if rawCode.hasPrefix("math ") {
            let mathExpr = String(rawCode.dropFirst(5))
            return "<span class=\"math-inline\" data-expr=\"\(escapeHTML(mathExpr))\"></span>"
        }
        return "<code>\(escapeHTML(rawCode))</code>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Result {
        let lang = codeBlock.language ?? ""
        let code = escapeHTML(codeBlock.code)

        // Mermaid: render as div for Mermaid.js
        if lang.lowercased() == "mermaid" {
            return "<div class=\"mermaid\">\(codeBlock.code)</div>\n"
        }

        // ECharts: render as div with JSON config
        if lang.lowercased() == "echarts" {
            return "<div class=\"echarts echarts-container\" data-config=\"\(escapeHTML(codeBlock.code))\"></div>\n"
        }

        // Math: one markdown parity ` ```math ` -> KaTeX block
        if lang.lowercased() == "math" {
            return "<div class=\"math-block\" data-expr=\"\(escapeHTML(codeBlock.code))\"></div>\n"
        }

        return "<pre><code class=\"language-\(escapeHTML(lang))\">\(code)</code></pre>\n"
    }

    mutating func visitLink(_ link: Markdown.Link) -> Result {
        let href = escapeHTML(link.destination ?? "")
        let inner = link.children.map { visit($0) }.joined()
        return "<a href=\"\(href)\">\(inner)</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) -> Result {
        let raw = image.source ?? ""
        // Decode any percent-encoding from the markdown source so we have
        // the real filesystem path to feed into URL(fileURLWithPath:)
        let decoded = raw.removingPercentEncoding ?? raw

        let resolvedSrc: String
        if raw.hasPrefix("http://") || raw.hasPrefix("https://")
            || raw.hasPrefix("data:") || raw.hasPrefix("file://") {
            resolvedSrc = raw                           // already a valid URL
        } else if decoded.hasPrefix("/") {
            // Absolute local path → URL(fileURLWithPath:) encodes spaces correctly
            resolvedSrc = URL(fileURLWithPath: decoded).absoluteString
        } else if !decoded.isEmpty, let base = baseDirectory {
            // Relative path (e.g. ./photo.png or sub/photo.png).
            // Strip leading ./ before appending so URL resolution is clean.
            let clean = decoded.hasPrefix("./") ? String(decoded.dropFirst(2)) : decoded
            let resolved = base.appendingPathComponent(clean)
            resolvedSrc = resolved.absoluteString
        } else {
            resolvedSrc = raw
        }
        let src = escapeHTML(resolvedSrc)
        let alt = escapeHTML(image.plainText)
        return "<img src=\"\(src)\" alt=\"\(alt)\">"
    }

    mutating func visitListItem(_ listItem: ListItem) -> Result {
        let inner = listItem.children.map { visit($0) }.joined()
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            return "<li><input type=\"checkbox\"\(checked) disabled> \(inner)</li>\n"
        }
        return "<li>\(inner)</li>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> Result {
        let items = orderedList.children.map { visit($0) }.joined()
        return "<ol>\n\(items)</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> Result {
        let items = unorderedList.children.map { visit($0) }.joined()
        return "<ul>\n\(items)</ul>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> Result {
        let inner = blockQuote.children.map { visit($0) }.joined()
        return "<blockquote>\n\(inner)</blockquote>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> Result {
        "<hr>\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> Result { " " }
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> Result { "<br>\n" }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> Result {
        "<del>\(strikethrough.children.map { visit($0) }.joined())</del>"
    }

    mutating func visitTable(_ table: Markdown.Table) -> Result {
        var html = "<table>\n"
        let head = table.head
        if head.childCount > 0 {
            html += "<thead><tr>"
            for cell in head.cells {
                html += "<th>\(cell.children.map { visit($0) }.joined())</th>"
            }
            html += "</tr></thead>\n"
        }
        html += "<tbody>\n"
        for row in table.body.rows {
            html += "<tr>"
            for cell in row.cells {
                html += "<td>\(cell.children.map { visit($0) }.joined())</td>"
            }
            html += "</tr>\n"
        }
        html += "</tbody></table>\n"
        return html
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> Result {
        inlineHTML.rawHTML
    }

    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) -> Result {
        htmlBlock.rawHTML
    }

    // MARK: - Helpers

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
