import SwiftUI

// MARK: - StartScreenView

struct StartScreenView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    private var sessionManager: SessionManager { SessionManager.shared }

    @State private var hoveredItemURL: URL? = nil

    var body: some View {
        HStack(spacing: 0) {
            // ── Left: Branding + Actions ─────────────────────────────
            leftPanel
                .frame(width: 260)
                .background(Color(.windowBackgroundColor).opacity(0.5))

            Divider()

            // ── Right: Recent Items ──────────────────────────────────
            rightPanel
                .frame(minWidth: 340, idealWidth: 400)
        }
        .frame(width: 660, height: 440)
        .background(.ultraThinMaterial)
        .onReceive(NotificationCenter.default.publisher(for: .startScreenShouldClose)) { _ in
            dismissWindow(id: "start-screen")
        }
    }

    // MARK: - Left Panel

    @ViewBuilder
    private var leftPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon + name
            VStack(spacing: 12) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }

                Text("True Markdown")
                    .font(.system(size: 24, weight: .bold))

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Version \(version)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
                .frame(height: 32)

            // Action buttons
            VStack(spacing: 10) {
                StartScreenButton(
                    title: "Open File",
                    subtitle: "Open a Markdown document",
                    icon: "doc.text"
                ) {
                    NSDocumentController.shared.openDocument(nil)
                }

                StartScreenButton(
                    title: "Open Folder",
                    subtitle: "Open a project folder",
                    icon: "folder"
                ) {
                    openFolder()
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.vertical, 24)
    }

    // MARK: - Right Panel (Recent Items)

    @ViewBuilder
    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Recent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !sessionManager.recentHistory.isEmpty {
                    Button("Clear") {
                        sessionManager.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if sessionManager.recentHistory.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No Recent Items")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Files and folders you open\nwill appear here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(sessionManager.recentHistory) { item in
                            RecentItemRow(
                                item: item,
                                isHovered: hoveredItemURL == item.url
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openRecentItem(item)
                            }
                            .onHover { hovering in
                                hoveredItemURL = hovering ? item.url : nil
                            }
                            .contextMenu {
                                Button("Show in Finder") {
                                    NSWorkspace.shared.selectFile(
                                        item.url.path,
                                        inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path
                                    )
                                }
                                Divider()
                                Button("Remove from Recent") {
                                    sessionManager.removeFromHistory(url: item.url)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Actions

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.message = "Choose a folder to open in True Markdown"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWindow(id: "folder-browser", value: url)
    }

    private func openRecentItem(_ item: RecentItem) {
        guard item.isAccessible else {
            sessionManager.removeFromHistory(url: item.url)
            return
        }
        switch item.type {
        case .folder:
            openWindow(id: "folder-browser", value: item.url)
        case .file:
            NSDocumentController.shared.openDocument(
                withContentsOf: item.url,
                display: true
            ) { _, _, _ in }
        }
    }
}

// MARK: - StartScreenButton

private struct StartScreenButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered
                        ? Color.accentColor.opacity(0.1)
                        : Color(.controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - RecentItemRow

private struct RecentItemRow: View {
    let item: RecentItem
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: item.type == .folder ? "folder.fill" : "doc.text.fill")
                .font(.system(size: 14))
                .foregroundStyle(item.type == .folder ? Color.accentColor : .secondary)
                .frame(width: 20)

            // Name + path
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.parentPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            // Relative date
            Text(item.lastOpened, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Group {
                if isHovered {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(.selectedContentBackgroundColor).opacity(0.4))
                        .padding(.horizontal, 6)
                }
            }
        )
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}
