import Foundation

// MARK: - FileNode

/// Represents a single node (file or folder) in the folder tree.
@Observable
final class FileNode: Identifiable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool

    var children: [FileNode] = []
    var isExpanded: Bool = false

    /// Whether this node can be opened in the editor (markdown files only).
    var isMarkdown: Bool {
        guard !isDirectory else { return false }
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    init(url: URL) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }

    /// Loads direct children from the file system (sorted: folders first, then files, alphabetically).
    func loadChildren() {
        guard isDirectory else { return }
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            )
            let nodes = contents
                .map { FileNode(url: $0) }
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            self.children = nodes
        } catch {
            self.children = []
        }
    }

    /// Toggle expanded state, loading children on first expand.
    func toggle() {
        if !isExpanded && children.isEmpty {
            loadChildren()
        }
        isExpanded.toggle()
    }
}
