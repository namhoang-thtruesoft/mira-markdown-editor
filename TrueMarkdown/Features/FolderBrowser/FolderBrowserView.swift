import SwiftUI

// MARK: - FolderBrowserView

/// Sidebar view showing the folder file tree.
struct FolderBrowserView: View {
    let rootNode: FileNode
    let selectedURL: URL?
    let onSelectFile: (URL) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Show children of root directly (not root itself)
                ForEach(rootNode.children) { node in
                    FileTreeRow(
                        node: node,
                        selectedURL: selectedURL,
                        depth: 0,
                        onSelectFile: onSelectFile
                    )
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.controlBackgroundColor))
        .onAppear {
            rootNode.loadChildren()
        }
    }
}

// MARK: - FileTreeRow

private struct FileTreeRow: View {
    @State var node: FileNode
    let selectedURL: URL?
    let depth: Int
    let onSelectFile: (URL) -> Void

    private var isSelected: Bool { node.url == selectedURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent
                .contentShape(Rectangle())
                .onTapGesture {
                    if node.isDirectory {
                        node.toggle()
                    } else if node.isMarkdown {
                        onSelectFile(node.url)
                    }
                }

            // Children (when expanded)
            if node.isDirectory && node.isExpanded {
                ForEach(node.children) { child in
                    FileTreeRow(
                        node: child,
                        selectedURL: selectedURL,
                        depth: depth + 1,
                        onSelectFile: onSelectFile
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: 4) {
            // Indent
            Spacer()
                .frame(width: CGFloat(depth) * 16)

            // Chevron for folders
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: node.isExpanded)
                    .frame(width: 12)
            } else {
                Spacer().frame(width: 12)
            }

            // Icon
            Image(systemName: fileIcon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            // Name
            Text(node.name)
                .font(.system(size: 12))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.trailing, 8)
        .background(rowBackground)
        .cornerRadius(5)
        .padding(.horizontal, 6)
    }

    private var fileIcon: String {
        if node.isDirectory {
            return node.isExpanded ? "folder.fill" : "folder"
        } else if node.isMarkdown {
            return "doc.text"
        } else {
            return "doc"
        }
    }

    private var iconColor: Color {
        if node.isDirectory { return .accentColor }
        if node.isMarkdown { return Color(.labelColor) }
        return .secondary
    }

    private var labelColor: Color {
        if node.isMarkdown || node.isDirectory { return Color(.labelColor) }
        return .secondary
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(0.15))
        } else {
            Color.clear
        }
    }
}
