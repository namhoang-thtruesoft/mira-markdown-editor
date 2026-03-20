import Foundation
import AppKit

// MARK: - FolderWindowManager

/// Manages state for a folder-mode window: which folder is open,
/// which file is selected, and its text content.
@MainActor @Observable
final class FolderWindowManager {
    var folderURL: URL
    var selectedFileURL: URL? = nil
    var fileContent: String = ""
    var isLoading: Bool = false
    var loadError: String? = nil

    init(folderURL: URL) {
        self.folderURL = folderURL
    }

    /// Load a markdown file from disk into `fileContent`.
    func loadFile(url: URL) {
        guard url != selectedFileURL else { return }
        isLoading = true
        loadError = nil
        selectedFileURL = url
        Task { @MainActor in
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                self.fileContent = content
                self.isLoading = false
            } catch {
                self.fileContent = ""
                self.loadError = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    /// Save current `fileContent` back to `selectedFileURL`.
    func saveCurrentFile() {
        guard let url = selectedFileURL else { return }
        do {
            try fileContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
