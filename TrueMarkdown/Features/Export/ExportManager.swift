import Foundation
import WebKit
import AppKit

// MARK: - ExportManager

@MainActor
final class ExportManager {
    private weak var webView: WKWebView?

    init(webView: WKWebView?) {
        self.webView = webView
    }

    // MARK: - PDF

    func exportPDF() async {
        guard let webView = webView else { return }
        let config = WKPDFConfiguration()
        do {
            let data = try await webView.pdf(configuration: config)
            savePanel(data: data, name: "document.pdf", contentType: .pdf)
        } catch {
            presentError(error)
        }
    }

    // MARK: - HTML (self-contained)

    func exportHTML(rawMarkdown: String) {
        let document = MarkdownParser.parse(rawMarkdown)
        let bodyHTML = HTMLRenderer.render(document)
        let fullHTML = """
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="UTF-8"><title>True Markdown Export</title></head>
        <body style="max-width:740px;margin:0 auto;padding:40px 20px;font-family:-apple-system,sans-serif;line-height:1.7">
        \(bodyHTML)
        </body></html>
        """
        guard let data = fullHTML.data(using: .utf8) else { return }
        savePanel(data: data, name: "document.html", contentType: .html)
    }

    // MARK: - Markdown (copy to clipboard)

    func copyMarkdown(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - PNG (snapshot)

    func exportPNG() async {
        guard let webView = webView else { return }
        let config = WKSnapshotConfiguration()
        do {
            let image = try await webView.takeSnapshot(configuration: config)
            guard let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }
            savePanel(data: pngData, name: "document.png", contentType: .png)
        } catch {
            presentError(error)
        }
    }

    // MARK: - Helpers

    private func savePanel(data: Data, name: String, contentType: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [contentType]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    private func presentError(_ error: Error) {
        NSApp.presentError(error)
    }
}

// UTType helpers
import UniformTypeIdentifiers
extension UTType {
    static let html = UTType("public.html")!
}
