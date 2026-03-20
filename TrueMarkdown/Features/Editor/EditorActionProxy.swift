import Foundation
import AppKit

// MARK: - Editor Insertion API

/// Shared state for the editor's NSTextView — allows external callers
/// (toolbar, command palette) to insert text at the current cursor position.
@MainActor
final class EditorActionProxy: ObservableObject {
    weak var textView: NSTextView?

    /// Set by ContentView when a document URL is known, used to compute relative image paths.
    var documentURL: URL? = nil

    // MARK: - Text Insertion

    func insertOrWrap(before: String, after: String = "") {
        guard let tv = textView else { return }
        let selected = tv.selectedRange()
        let selectedText = (tv.string as NSString).substring(with: selected)

        let replacement: String
        if selectedText.isEmpty {
            replacement = before + after
        } else {
            replacement = before + selectedText + after
        }

        if tv.shouldChangeText(in: selected, replacementString: replacement) {
            tv.replaceCharacters(in: selected, with: replacement)
            tv.didChangeText()
            // Position cursor inside the markers if no selection
            if selectedText.isEmpty {
                let cursorPos = selected.location + before.count
                tv.setSelectedRange(NSRange(location: cursorPos, length: 0))
            }
        }
    }

    func insertAtLineStart(prefix: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let nsString = tv.string as NSString
        let lineRange = nsString.lineRange(for: range)
        let line = nsString.substring(with: lineRange)

        let replacement: String
        if line.hasPrefix(prefix) {
            // Toggle off
            replacement = String(line.dropFirst(prefix.count))
        } else {
            // Remove other heading prefixes first, then add new one
            let stripped = line.replacingOccurrences(of: "^#{1,6} ", with: "", options: .regularExpression)
            replacement = prefix + stripped
        }

        if tv.shouldChangeText(in: lineRange, replacementString: replacement) {
            tv.replaceCharacters(in: lineRange, with: replacement)
            tv.didChangeText()
        }
    }

    // MARK: - Quick Insert Templates

    func insertBold()          { insertOrWrap(before: "**", after: "**") }
    func insertItalic()        { insertOrWrap(before: "*", after: "*") }
    func insertStrikethrough() { insertOrWrap(before: "~~", after: "~~") }
    func insertInlineCode()    { insertOrWrap(before: "`", after: "`") }
    func insertLink()          { insertOrWrap(before: "[", after: "](url)") }
    /// Opens a native macOS file picker, copies the image to a companion assets
    /// folder, and inserts `![](relative/path)` at the current cursor position.
    func insertImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Insert"

        guard panel.runModal() == .OK, let pickedURL = panel.url else { return }

        // Get the best path (relative if possible, else absolute)
        let assetManager = ImageAssetManager(documentURL: documentURL)
        let rawPath = assetManager.copyImageToAssets(from: pickedURL) ?? pickedURL.path

        // Percent-encode path so spaces and special chars are valid in markdown/HTML.
        // Encode each path component separately to preserve the "/" separators.
        let encodedPath = rawPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        // Restore leading slash for absolute paths
        let markdownPath = rawPath.hasPrefix("/") && !encodedPath.hasPrefix("/")
            ? "/" + encodedPath : encodedPath

        // Insert ![](path) at cursor, position cursor between [] for alt text
        let markdown = "![](\(markdownPath))"
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if tv.shouldChangeText(in: range, replacementString: markdown) {
            tv.replaceCharacters(in: range, with: markdown)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: range.location + 2, length: 0))
        }
    }
    func insertHeading(_ level: Int) { insertAtLineStart(prefix: String(repeating: "#", count: level) + " ") }

    func insertCodeBlock(language: String = "") {
        guard let tv = textView else { return }
        let template = "```\(language)\n\n```"
        let range = tv.selectedRange()
        if tv.shouldChangeText(in: range, replacementString: template) {
            tv.replaceCharacters(in: range, with: template)
            tv.didChangeText()
            // Place cursor inside the block
            tv.setSelectedRange(NSRange(location: range.location + 3 + language.count + 1, length: 0))
        }
    }

    func insertMermaid(type: String) {
        let templates: [String: String] = [
            "flowchart": "```mermaid\nflowchart TD\n    A[Start] --> B{Decision}\n    B -->|Yes| C[Result]\n    B -->|No| D[Other]\n```",
            "sequence": "```mermaid\nsequenceDiagram\n    A->>B: Message\n    B-->>A: Response\n```",
            "gantt":    "```mermaid\ngantt\n    title Project\n    dateFormat YYYY-MM-DD\n    section Phase\n    Task :a1, 2024-01-01, 7d\n```",
            "pie":      "```mermaid\npie\n    title Distribution\n    \"A\" : 40\n    \"B\" : 35\n    \"C\" : 25\n```",
            "class":    "```mermaid\nclassDiagram\n    class Animal{\n      +String name\n      +speak()\n    }\n```"
        ]
        let template = templates[type] ?? "```mermaid\ngraph TD;\n    A-->B;\n```"
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if tv.shouldChangeText(in: range, replacementString: template) {
            tv.replaceCharacters(in: range, with: template)
            tv.didChangeText()
        }
    }

    func insertTable() {
        let template = """
        | Column 1 | Column 2 | Column 3 |
        |----------|----------|----------|
        | Cell 1   | Cell 2   | Cell 3   |
        | Cell 4   | Cell 5   | Cell 6   |
        """
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if tv.shouldChangeText(in: range, replacementString: template) {
            tv.replaceCharacters(in: range, with: template)
            tv.didChangeText()
        }
    }

    // MARK: - Scroll to range (TOC sync)

    func insertBlockquote() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let nsString = tv.string as NSString
        let lineRange = nsString.lineRange(for: range)
        let line = nsString.substring(with: lineRange)
        let replacement = line.hasPrefix("> ")
            ? String(line.dropFirst(2))
            : "> " + line
        if tv.shouldChangeText(in: lineRange, replacementString: replacement) {
            tv.replaceCharacters(in: lineRange, with: replacement)
            tv.didChangeText()
        }
    }

    func insertHorizontalRule() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let template = "\n---\n"
        if tv.shouldChangeText(in: range, replacementString: template) {
            tv.replaceCharacters(in: range, with: template)
            tv.didChangeText()
        }
    }

    func scrollTo(characterIndex: Int) {
        guard let tv = textView else { return }
        let range = NSRange(location: characterIndex, length: 0)
        tv.scrollRangeToVisible(range)
        tv.setSelectedRange(range)
    }

    // MARK: - Search & Replace

    /// Cached match ranges for the current search query.
    private var searchMatches: [NSRange] = []

    /// Highlight all occurrences of `query` in the editor.
    /// Returns the number of matches found.
    @discardableResult
    func highlightMatches(query: String, caseSensitive: Bool) -> Int {
        guard let tv = textView, let lm = tv.layoutManager else {
            searchMatches = []
            return 0
        }

        // Clear previous highlights
        let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

        guard !query.isEmpty else {
            searchMatches = []
            return 0
        }

        let nsString = tv.string as NSString
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsString.length)

        while searchRange.location < nsString.length {
            let found = nsString.range(of: query, options: options, range: searchRange)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            // Apply yellow highlight
            lm.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), forCharacterRange: found)
            searchRange.location = found.location + found.length
            searchRange.length = nsString.length - searchRange.location
        }

        searchMatches = ranges
        return ranges.count
    }

    /// Scroll to and highlight the match at `index` with an accent color.
    func scrollToMatch(index: Int) {
        guard let tv = textView, let lm = tv.layoutManager,
              index >= 0, index < searchMatches.count else { return }

        // Reset all matches to yellow
        for range in searchMatches {
            lm.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), forCharacterRange: range)
        }

        // Highlight current match in orange
        let current = searchMatches[index]
        lm.addTemporaryAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.55), forCharacterRange: current)

        tv.scrollRangeToVisible(current)
        tv.setSelectedRange(current)
    }

    /// Replace the match at `index` and return the updated match count.
    @discardableResult
    func replaceMatch(at index: Int, with replacement: String, query: String, caseSensitive: Bool) -> Int {
        guard let tv = textView,
              index >= 0, index < searchMatches.count else { return searchMatches.count }

        let range = searchMatches[index]
        if tv.shouldChangeText(in: range, replacementString: replacement) {
            tv.replaceCharacters(in: range, with: replacement)
            tv.didChangeText()
        }

        // Re-run search to get updated ranges
        return highlightMatches(query: query, caseSensitive: caseSensitive)
    }

    /// Replace all occurrences. Returns the number replaced.
    @discardableResult
    func replaceAll(query: String, with replacement: String, caseSensitive: Bool) -> Int {
        guard let tv = textView, !query.isEmpty else { return 0 }

        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        let count = searchMatches.count
        // Replace from end to preserve earlier ranges
        for range in searchMatches.reversed() {
            if tv.shouldChangeText(in: range, replacementString: replacement) {
                tv.replaceCharacters(in: range, with: replacement)
                tv.didChangeText()
            }
        }

        // Refresh highlights (should be zero matches now)
        highlightMatches(query: query, caseSensitive: caseSensitive)
        return count
    }

    /// Remove all search highlights.
    func clearSearchHighlights() {
        guard let tv = textView, let lm = tv.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        searchMatches = []
    }
}
