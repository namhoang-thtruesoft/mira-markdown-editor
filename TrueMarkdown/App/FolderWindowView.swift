import SwiftUI
import WebKit
import Combine

// MARK: - FolderWindowView

/// Top-level view shown when a folder is opened.
/// Left: file tree sidebar  |  Right: editor + preview for selected file.
struct FolderWindowView: View {
    @State private var manager: FolderWindowManager
    @State private var rootNode: FileNode

    // Editor/preview state
    @State private var viewModeManager: ViewModeManager
    @State private var actionProxy = EditorActionProxy()
    @State private var renderedHTML: String = ""
    @State private var tocEntries: [TOCEntry] = []
    @State private var scrollTarget: String? = nil
    @State private var exportWebView: WKWebView? = nil
    @State private var showTOC: Bool = false

    // Search state
    @State private var showSearch = false
    @State private var searchState = SearchState()
    @State private var showCommandPalette = false
    @State private var debounceTask: Task<Void, Never>?

    @AppStorage("editorFontSize") private var fontSize: Double = 15
    @State private var editorFraction: CGFloat = 0.5
    @GestureState private var dividerDragOffset: CGFloat = 0
    @Environment(\.openWindow) private var openWindow

    // Folder sidebar visibility (controlled by right-side toolbar button)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(folderURL: URL) {
        let mgr = FolderWindowManager(folderURL: folderURL)
        self._manager = State(initialValue: mgr)
        let root = FileNode(url: folderURL)
        self._rootNode = State(initialValue: root)
        self._viewModeManager = State(initialValue: ViewModeManager(documentURL: nil))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle(rootNode.name)
        .toolbar {
            ToolbarView(
                viewModeManager: viewModeManager,
                showTOC: $showTOC,
                onExport: handleExport,
                actionProxy: manager.selectedFileURL != nil ? actionProxy : nil,
                showCommandPalette: $showCommandPalette
            )
        }
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewStyle(.prominentDetail)
        .overlay(alignment: .top) { commandPaletteOverlay }
        .onReceive(NotificationCenter.default.publisher(for: .openFolderURL)) { note in
            guard let url = note.object as? URL else { return }
            openWindow(id: "folder-browser", value: url)
        }
        .onChange(of: manager.fileContent) { _, newText in scheduleRender(newText) }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSearch)) { _ in
            showSearch.toggle()
            if !showSearch { dismissSearch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findNext)) { _ in
            searchState.nextMatch(); navigateToCurrentMatch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .findPrevious)) { _ in
            searchState.previousMatch(); navigateToCurrentMatch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .setViewMode)) { note in
            if let raw = note.object as? String, let mode = ViewMode(rawValue: raw) {
                viewModeManager.setMode(mode)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .changeFontSize)) { note in
            if let delta = note.object as? Double {
                if delta == 0 { fontSize = 15 }
                else { fontSize = min(max(fontSize + delta, 10), 32) }
            }
        }
        .onAppear {
            AppCoordinator.shared.registerFolder(manager.folderURL)
            SessionManager.shared.trackOpen(url: manager.folderURL, type: .folder)
            NotificationCenter.default.post(name: .startScreenShouldClose, object: nil)
        }
        .onDisappear {
            AppCoordinator.shared.unregisterFolder(manager.folderURL)
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            // ── Folder header ──────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor)
                Text(rootNode.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // ── File tree ─────────────────────────────────────────────────
            FolderBrowserView(
                rootNode: rootNode,
                selectedURL: manager.selectedFileURL,
                onSelectFile: { url in
                    manager.loadFile(url: url)
                    actionProxy.documentURL = url
                    renderNow(manager.fileContent)
                }
            )
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 380)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if manager.isLoading {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = manager.loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("Could not open file")
                    .font(.headline)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if manager.selectedFileURL == nil {
            emptyState
        } else {
            editorPreviewContent
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a file")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Choose a Markdown file from the sidebar to open it.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var editorPreviewContent: some View {
        GeometryReader { proxy in
            let mode = viewModeManager.mode
            let total = proxy.size.width
            let tocW: CGFloat = showTOC ? 260 : 0
            let editorW = max(editorWidth(mode: mode, total: total - tocW), 0)
            let previewW = max(total - tocW - editorW - (mode == .dual ? 10 : 0), 0)

            HStack(spacing: 0) {
                // Editor
                EditorView(
                    text: Binding(
                        get: { manager.fileContent },
                        set: { manager.fileContent = $0 }
                    ),
                    fontSize: CGFloat(fontSize),
                    actionProxy: actionProxy
                )
                .frame(width: editorW)
                .opacity(mode == .preview ? 0 : 1)
                .clipped()
                .allowsHitTesting(mode != .preview)
                .overlay(alignment: .top) {
                    if showSearch && mode != .preview {
                        searchBarContent
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                    }
                }

                // Divider (dual mode)
                if mode == .dual {
                    DividerHandleFolderView()
                        .frame(width: 10)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering { NSCursor.resizeLeftRight.push() }
                            else { NSCursor.pop() }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .updating($dividerDragOffset) { value, state, _ in
                                    state = value.translation.width
                                }
                                .onEnded { value in
                                    let delta = value.translation.width / total
                                    editorFraction = min(0.75, max(0.25, editorFraction + delta))
                                }
                        )
                }

                // Preview
                PreviewView(
                    htmlContent: renderedHTML,
                    scrollTarget: scrollTarget,
                    fontSize: fontSize,
                    onWebViewCreated: { exportWebView = $0 }
                )
                .frame(width: previewW)
                .opacity(mode == .edit ? 0 : 1)
                .clipped()
                .allowsHitTesting(mode != .edit)
                .overlay(alignment: .top) {
                    if showSearch && mode == .preview {
                        searchBarContent
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                    }
                }

                // ── TOC Panel (right side) ──────────────────────────────
                if showTOC {
                    Divider()
                    TOCView(entries: tocEntries) { entry in
                        scrollTarget = entry.blockId
                        let charIndex = characterIndex(forLine: entry.lineNumber, in: manager.fileContent)
                        actionProxy.scrollTo(characterIndex: charIndex)
                    }
                    .frame(width: tocW - 1)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: mode)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showTOC)
        }
        .frame(minWidth: 420)
    }

    private func editorWidth(mode: ViewMode, total: CGFloat) -> CGFloat {
        switch mode {
        case .edit:    return total
        case .preview: return 0
        case .dual:
            let preferred = editorFraction * total + dividerDragOffset
            return min(total - 208, max(200, preferred))
        }
    }

    // MARK: - Search Bar

    private var searchBarContent: some View {
        SearchBarView(
            searchState: searchState,
            isVisible: $showSearch,
            onQueryChanged: { performSearch() },
            onNavigate: { navigateToCurrentMatch() },
            onReplace: { handleReplace() },
            onReplaceAll: { handleReplaceAll() },
            onDismiss: { showSearch = false; dismissSearch() }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(50)
    }

    // MARK: - Command Palette Overlay

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        ZStack(alignment: .top) {
            if showCommandPalette {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { showCommandPalette = false }
            }
            if showCommandPalette {
                CommandPaletteView(isPresented: $showCommandPalette)
                    .padding(.top, 40)
                    .zIndex(100)
                    .keyboardShortcut("k")
                    .allowsHitTesting(true)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: showCommandPalette)
    }

    // MARK: - Rendering

    private func renderNow(_ text: String) {
        let doc = MarkdownParser.parse(text)
        let baseDir = manager.selectedFileURL?.deletingLastPathComponent()
        renderedHTML = HTMLRenderer.renderWithBlockIDs(doc, baseDirectory: baseDir)
        tocEntries = TOCExtractor.extract(from: doc)
    }

    /// Converts a 1-indexed line number to a character offset in the source text.
    private func characterIndex(forLine lineNumber: Int, in text: String) -> Int {
        let lines = text.components(separatedBy: "\n")
        let targetLine = max(0, lineNumber - 1)
        return lines.prefix(targetLine).reduce(0) { $0 + $1.count + 1 }
    }

    private func scheduleRender(_ text: String) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            renderNow(text)
        }
    }

    // MARK: - Search Logic

    private func performSearch() {
        let query = searchState.query
        let cs = searchState.caseSensitive
        let mode = viewModeManager.mode

        if mode != .preview {
            let count = actionProxy.highlightMatches(query: query, caseSensitive: cs)
            searchState.matchCount = count
        } else {
            actionProxy.clearSearchHighlights()
        }

        if mode != .edit, let webView = exportWebView {
            let csJS = cs ? "true" : "false"
            let escapedQuery = query
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("highlightSearch('\(escapedQuery)', \(csJS))") { result, _ in
                if mode == .preview, let count = result as? Int {
                    self.searchState.matchCount = count
                }
            }
        } else if let webView = exportWebView {
            webView.evaluateJavaScript("clearSearchHighlight(); null;", completionHandler: nil)
        }

        searchState.currentMatchIndex = 0
        navigateToCurrentMatch()
    }

    private func navigateToCurrentMatch() {
        let index = searchState.currentMatchIndex
        let mode = viewModeManager.mode
        if mode != .preview { actionProxy.scrollToMatch(index: index) }
        if mode != .edit, let webView = exportWebView {
            webView.evaluateJavaScript("scrollToSearchMatch(\(index)); null;", completionHandler: nil)
        }
    }

    private func handleReplace() {
        let newCount = actionProxy.replaceMatch(
            at: searchState.currentMatchIndex,
            with: searchState.replacement,
            query: searchState.query,
            caseSensitive: searchState.caseSensitive
        )
        searchState.matchCount = newCount
        if searchState.currentMatchIndex >= newCount {
            searchState.currentMatchIndex = max(0, newCount - 1)
        }
        navigateToCurrentMatch()
    }

    private func handleReplaceAll() {
        let _ = actionProxy.replaceAll(
            query: searchState.query,
            with: searchState.replacement,
            caseSensitive: searchState.caseSensitive
        )
        searchState.matchCount = 0
        searchState.currentMatchIndex = 0
    }

    private func dismissSearch() {
        actionProxy.clearSearchHighlights()
        if let webView = exportWebView {
            webView.evaluateJavaScript("clearSearchHighlight(); null;", completionHandler: nil)
        }
        searchState.matchCount = 0
        searchState.currentMatchIndex = 0
    }

    // MARK: - Export

    private func handleExport(_ format: ExportFormat) {
        guard let webView = exportWebView else { return }
        let mgr = ExportManager(webView: webView)
        Task {
            switch format {
            case .pdf:      await mgr.exportPDF()
            case .html:     mgr.exportHTML(rawMarkdown: manager.fileContent)
            case .markdown: mgr.copyMarkdown(manager.fileContent)
            case .png:      await mgr.exportPNG()
            }
        }
    }
}

// MARK: - DividerHandleFolderView

private struct DividerHandleFolderView: View {
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Color(.separatorColor)
                .frame(width: 1)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(.thickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5)
                        .strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.1), lineWidth: 0.5)
                )
                .frame(width: 4, height: isHovered ? 36 : 28)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        }
        .onHover { hovering in isHovered = hovering }
    }
}
