import Testing
import Foundation
@testable import TrueMarkdownAppStore

// MARK: - MarkdownParser Tests

@Suite("MarkdownParser")
struct MarkdownParserTests {
    @Test("Parse a simple heading")
    func parseHeading() {
        let doc = MarkdownParser.parse("# Hello World")
        let children = Array(doc.children)
        #expect(children.count == 1)
    }

    @Test("Parse paragraph")
    func parseParagraph() {
        let doc = MarkdownParser.parse("Hello, world!")
        #expect(Array(doc.children).count == 1)
    }
}

// MARK: - HTMLRenderer Tests

@Suite("HTMLRenderer")
struct HTMLRendererTests {
    @Test("Heading renders with correct tag")
    func headingHTML() {
        let doc = MarkdownParser.parse("# Title")
        let html = HTMLRenderer.render(doc)
        #expect(html.contains("<h1"))
        #expect(html.contains("Title"))
    }

    @Test("Mermaid code block renders as mermaid div")
    func mermaidBlock() {
        let md = """
        ```mermaid
        graph TD; A-->B;
        ```
        """
        let doc = MarkdownParser.parse(md)
        let html = HTMLRenderer.render(doc)
        #expect(html.contains("class=\"mermaid\""))
    }

    @Test("Bold renders as strong tag")
    func boldText() {
        let doc = MarkdownParser.parse("**bold**")
        let html = HTMLRenderer.render(doc)
        #expect(html.contains("<strong>"))
    }

    @Test("GFM table renders as table element")
    func gfmTable() {
        let md = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let doc = MarkdownParser.parse(md)
        let html = HTMLRenderer.render(doc)
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>"))
    }
}

// MARK: - IncrementalRenderer Tests

@Suite("IncrementalRenderer")
@MainActor
struct IncrementalRendererTests {
    @Test("No patches when text unchanged")
    func noPatchesOnSameText() async {
        let renderer = IncrementalRenderer()
        let _ = renderer.diff(newText: "# Hello")
        let patches = renderer.diff(newText: "# Hello")
        #expect(patches.isEmpty)
    }

    @Test("Only changed block is patched")
    func onlyChangedBlockPatched() async {
        let renderer = IncrementalRenderer()
        let _ = renderer.diff(newText: "# Title\n\nParagraph one.")
        let patches = renderer.diff(newText: "# Title\n\nParagraph two.")
        // Only block-1 (the paragraph) changed
        #expect(patches.count == 1)
        #expect(patches.first?.blockId == "block-1")
    }
}
