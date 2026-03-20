import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - ImageAssetManager
//
// Manages image assets for a Mira document.
// Copies local images to an assets folder alongside the .md file
// and returns the relative path for use in Markdown syntax.

final class ImageAssetManager {
    private let documentURL: URL?

    init(documentURL: URL?) {
        self.documentURL = documentURL
    }

    /// Returns the best path string to use in Markdown `![](path)` syntax:
    /// - Relative path if the image is already inside the document's directory tree.
    /// - Copies to `<docName>_assets/` and returns a relative path if the image is elsewhere.
    /// - Falls back to absolute path for unsaved documents or on copy failure.
    func copyImageToAssets(from sourceURL: URL) -> String? {
        guard let docURL = documentURL else {
            // Unsaved document — use absolute path
            return sourceURL.path
        }

        let docDir = docURL.deletingLastPathComponent().standardized
        let sourceDir = sourceURL.deletingLastPathComponent().standardized

        // ── Case 1: Image is already inside the document's directory tree ──
        // Use ./relative/path so the markdown stays git-portable and follows standard.
        if sourceDir.path.hasPrefix(docDir.path) {
            let relativePath = sourceURL.path
                .replacingOccurrences(of: docDir.path + "/", with: "")
            return "./" + relativePath
        }

        // ── Case 2: Image is outside → copy to companion assets folder ──
        let docName = docURL.deletingPathExtension().lastPathComponent
        let assetsDir = docDir.appendingPathComponent("\(docName)_assets", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: assetsDir,
                withIntermediateDirectories: true
            )
            let dest = assetsDir.appendingPathComponent(sourceURL.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.copyItem(at: sourceURL, to: dest)
            }
            // ./docName_assets/filename — relative path with ./ prefix
            return "./\(docName)_assets/\(sourceURL.lastPathComponent)"
        } catch {
            print("[ImageAssetManager] Failed to copy image: \(error)")
            return sourceURL.path   // absolute fallback
        }
    }

    // MARK: - Validate URL

    /// Returns true if the string is a valid http(s) URL.
    static func isWebURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}
