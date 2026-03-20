import SwiftUI
import WebKit
import Combine
import AppKit

// MARK: - ContentView

struct ContentView: View {
    @Binding var document: TrueMarkdownDocument
    @State private var viewModeManager: ViewModeManager
    @State private var documentState: DocumentState
    @State private var actionProxy = EditorActionProxy()
    @Environment(\.openWindow) private var openWindow

    // Preview state
    @State private var renderedHTML: String = ""
    @State private var tocEntries: [TOCEntry] = []
    @State private var scrollTarget: String? = nil
    @State private var exportWebView: WKWebView? = nil

    // UI state
    @State private var showTOC: Bool
    @State private var showCommandPalette = false
    @State private var debounceTask: Task<Void, Never>?

    // Search state
    @State private var showSearch = false
    @State private var searchState = SearchState()

    @AppStorage("editorFontSize") private var fontSize: Double = 15
    private let fileURL: URL?
    /// User's preferred editor/preview split in dual mode (0.0-1.0).
    @State private var editorFraction: CGFloat = 0.5
    /// Live drag offset (reset to 0 when gesture ends).
    @GestureState private var dividerDragOffset: CGFloat = 0

    init(document: Binding<TrueMarkdownDocument>, fileURL: URL? = nil) {
        self._document = document
        let state = DocumentState(fileURL: fileURL)
        self._documentState = State(initialValue: state)
        self._viewModeManager = State(initialValue: ViewModeManager(documentURL: fileURL))
        self._showTOC = State(initialValue: state.tocVisible)
        self.fileURL = fileURL
    }

    var body: some View {
        NavigationSplitView(
            sidebar: { tocSidebar },
            detail: { mainContent }
        )
        .toolbar {
            ToolbarView(
                viewModeManager: viewModeManager,
                showTOC: $showTOC,
                onExport: handleExport,
                actionProxy: actionProxy,
                showCommandPalette: $showCommandPalette
            )
        }
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewStyle(.prominentDetail)
        .overlay(alignment: .top) { commandPaletteOverlay }
        .onChange(of: document.text) { _, newText in scheduleRender(newText) }
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
        .onChange(of: showTOC) { _, v in documentState.tocVisible = v }
        .onReceive(NotificationCenter.default.publisher(for: .setViewMode)) { note in
            if let raw = note.object as? String, let mode = ViewMode(rawValue: raw) {
                viewModeManager.setMode(mode)
            }
        }
        .onAppear {
            registerCommands()
            renderNow(document.text)
            actionProxy.documentURL = fileURL
            // Track this file open for recent history
            if let url = fileURL {
                SessionManager.shared.trackOpen(url: url, type: .file)
            }
            // Close start screen if it's visible
            NotificationCenter.default.post(name: .startScreenShouldClose, object: nil)
            // Consume a folder URL that was selected before this view existed (startup case).
            if let url = AppCoordinator.shared.pendingFolderURL {
                AppCoordinator.shared.pendingFolderURL = nil
                openWindow(id: "folder-browser", value: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFolderURL)) { note in
            guard let url = note.object as? URL else { return }
            openWindow(id: "folder-browser", value: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .changeFontSize)) { note in
            if let delta = note.object as? Double {
                if delta == 0 {
                    fontSize = 15   // reset to default
                } else {
                    fontSize = min(max(fontSize + delta, 10), 32)
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var tocSidebar: some View {
        // Sidebar slot must exist for NavigationSplitView but TOC is now on the RIGHT.
        Color.clear
            .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
    }

    // MARK: - Search Bar (positioned per-panel)

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

    @ViewBuilder
    private var mainContent: some View {
        GeometryReader { proxy in
            let mode = viewModeManager.mode
            let total = proxy.size.width
            let tocW: CGFloat = showTOC ? 260 : 0
            let editorW = max(editorWidth(mode: mode, total: total - tocW), 0)
            let previewW = max(total - tocW - editorW - (mode == .dual ? 10 : 0), 0)

            HStack(spacing: 0) {
                // ── Editor (always alive) ───────────────────────────────────────
                EditorView(text: $document.text, fontSize: CGFloat(fontSize), actionProxy: actionProxy)
                    .frame(width: editorW)
                    .opacity(mode == .preview ? 0 : 1)
                    .clipped()
                    .allowsHitTesting(mode != .preview)
                    .overlay(alignment: .top) {
                        // Floating search bar on editor panel (edit & dual modes)
                        if showSearch && mode != .preview {
                            searchBarContent
                                .padding(.horizontal, 8)
                                .padding(.top, 6)
                        }
                    }

                // ── Drag-to-resize handle (dual mode only) ─────────────────
                if mode == .dual {
                    DividerHandle()
                    .frame(width: 10)          // wide hit area
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
                    .transition(.opacity)
                }

                // ── Preview (always alive — no WKWebView recreation) ────────
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
                    // Floating search bar on preview panel (preview-only mode)
                    if showSearch && mode == .preview {
                        searchBarContent
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                    }
                }

                // ── TOC Panel (right side) ──────────────────────────────────
                if showTOC {
                    Divider()
                    TOCView(entries: tocEntries) { entry in
                        scrollTarget = entry.blockId
                        let charIndex = characterIndex(forLine: entry.lineNumber, in: document.text)
                        actionProxy.scrollTo(characterIndex: charIndex)
                    }
                    .frame(width: tocW - 1) // -1 for divider
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: mode)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showTOC)
        }
        .frame(minWidth: 420)
    }

    /// Returns the editor's pixel width for a given mode.
    private func editorWidth(mode: ViewMode, total: CGFloat) -> CGFloat {
        switch mode {
        case .edit:    return total
        case .preview: return 0
        case .dual:
            // Apply live drag offset, clamped so neither panel can be < 200px
            let preferred = editorFraction * total + dividerDragOffset
            return min(total - 208, max(200, preferred))  // 8px handle
        }
    }

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        ZStack(alignment: .top) {
            // ── Dismiss background — full window, behind the palette ──────────
            // Any click outside the palette closes it.
            if showCommandPalette {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { showCommandPalette = false }
            }

            // ── The palette itself ────────────────────────────────────────────
            if showCommandPalette {
                CommandPaletteView(isPresented: $showCommandPalette)
                    .padding(.top, 40)
                    .zIndex(100)
                    // ⌘K a second time also closes
                    .keyboardShortcut("k")
                    .allowsHitTesting(true)       // palette captures its own clicks
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: showCommandPalette)
    }


    // MARK: - Rendering

    /// Immediate (no debounce) — called on first appear.
    private func renderNow(_ text: String) {
        let doc = MarkdownParser.parse(text)
        let baseDir = fileURL?.deletingLastPathComponent()
        renderedHTML = HTMLRenderer.renderWithBlockIDs(doc, baseDirectory: baseDir)
        tocEntries = TOCExtractor.extract(from: doc)
    }

    /// Converts a 1-indexed line number to a character offset in the source text.
    private func characterIndex(forLine lineNumber: Int, in text: String) -> Int {
        let lines = text.components(separatedBy: "\n")
        let targetLine = max(0, lineNumber - 1)
        return lines.prefix(targetLine).reduce(0) { $0 + $1.count + 1 }  // +1 for '\n'
    }

    /// Debounced — called on every keystroke.
    private func scheduleRender(_ text: String) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            renderNow(text)
        }
    }

    // MARK: - Search Logic

    /// Run search across editor and/or preview based on current view mode.
    private func performSearch() {
        let query = searchState.query
        let cs = searchState.caseSensitive
        let mode = viewModeManager.mode

        // Editor search
        if mode != .preview {
            let count = actionProxy.highlightMatches(query: query, caseSensitive: cs)
            searchState.matchCount = count
        } else {
            actionProxy.clearSearchHighlights()
        }

        // Preview search
        if mode != .edit, let webView = exportWebView {
            let csJS = cs ? "true" : "false"
            let escapedQuery = query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
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

    /// Scroll to current match in both editor and preview.
    private func navigateToCurrentMatch() {
        let index = searchState.currentMatchIndex
        let mode = viewModeManager.mode

        if mode != .preview {
            actionProxy.scrollToMatch(index: index)
        }
        if mode != .edit, let webView = exportWebView {
            webView.evaluateJavaScript("scrollToSearchMatch(\(index)); null;", completionHandler: nil)
        }
    }

    /// Replace current match (editor only — replace in source markdown).
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

    /// Replace all matches (editor only).
    private func handleReplaceAll() {
        let _ = actionProxy.replaceAll(
            query: searchState.query,
            with: searchState.replacement,
            caseSensitive: searchState.caseSensitive
        )
        searchState.matchCount = 0
        searchState.currentMatchIndex = 0
    }

    /// Clean up highlights when search is dismissed.
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
        let manager = ExportManager(webView: webView)
        Task {
            switch format {
            case .pdf:      await manager.exportPDF()
            case .html:     manager.exportHTML(rawMarkdown: document.text)
            case .markdown: manager.copyMarkdown(document.text)
            case .png:      await manager.exportPNG()
            }
        }
    }

    // MARK: - Commands

    private func registerCommands() {
        guard CommandRegistry.shared.commands.isEmpty else { return }
        let proxy = actionProxy
        let vm = viewModeManager
        CommandRegistry.shared.register(contentsOf: [

            // ── View modes ──────────────────────────────────────────────────
            Command(title: "Edit Mode",    keywords: ["edit","write","mode"],   shortcut: "⌘⇧E") { vm.setMode(.edit) },
            Command(title: "Preview Mode", keywords: ["preview","read","mode"], shortcut: "⌘⇧P") { vm.setMode(.preview) },
            Command(title: "Dual Mode",    keywords: ["split","dual","mode"],   shortcut: "⌘⇧D") { vm.setMode(.dual) },

            // ── Inline formatting ────────────────────────────────────────────
            Command(title: "Bold",          keywords: ["bold","format"],         shortcut: "⌘B")   { proxy.insertBold() },
            Command(title: "Italic",        keywords: ["italic","format"],       shortcut: "⌘I")   { proxy.insertItalic() },
            Command(title: "Strikethrough", keywords: ["strike","delete"],       shortcut: "⌘⌥X")  { proxy.insertStrikethrough() },
            Command(title: "Inline Code",   keywords: ["code","inline","mono"],  shortcut: "⌘⌥C")  { proxy.insertInlineCode() },
            Command(title: "Link",          keywords: ["link","url","href"],     shortcut: "⌘⌥L")  { proxy.insertLink() },

            // ── Block elements ────────────────────────────────────────────────
            Command(title: "Code Block",       keywords: ["code","block","fence"],  shortcut: "⌘⌥K")  { proxy.insertCodeBlock() },
            Command(title: "Blockquote",       keywords: ["quote","block"],         shortcut: "⌘⌥Q")  { proxy.insertBlockquote() },
            Command(title: "Table",            keywords: ["table","grid"],          shortcut: "⌘⌥T")  { proxy.insertTable() },
            Command(title: "Image",            keywords: ["image","photo","pic"],   shortcut: "⌘⌥P")  { proxy.insertImage() },
            Command(title: "Horizontal Rule",  keywords: ["rule","divider","hr"],   shortcut: "⌘⌥H")  { proxy.insertHorizontalRule() },

            // ── Headings (⌘⌥ + level number — mirrors heading level) ─────────
            Command(title: "Heading 1", keywords: ["h1","heading","title"],   shortcut: "⌘⌥1") { proxy.insertHeading(1) },
            Command(title: "Heading 2", keywords: ["h2","heading","section"], shortcut: "⌘⌥2") { proxy.insertHeading(2) },
            Command(title: "Heading 3", keywords: ["h3","heading"],           shortcut: "⌘⌥3") { proxy.insertHeading(3) },
            Command(title: "Heading 4", keywords: ["h4","heading"],           shortcut: "⌘⌥4") { proxy.insertHeading(4) },
            Command(title: "Heading 5", keywords: ["h5","heading"],           shortcut: "⌘⌥5") { proxy.insertHeading(5) },
            Command(title: "Heading 6", keywords: ["h6","heading"],           shortcut: "⌘⌥6") { proxy.insertHeading(6) },

            // ── Diagrams ─────────────────────────────────────────────────────
            Command(title: "Mermaid Flowchart",    keywords: ["mermaid","flow","diagram"],  shortcut: "") { proxy.insertMermaid(type: "flowchart") },
            Command(title: "Mermaid Sequence",     keywords: ["mermaid","sequence","seq"],  shortcut: "") { proxy.insertMermaid(type: "sequence") },
            Command(title: "Mermaid Gantt Chart",  keywords: ["mermaid","gantt","timeline"],shortcut: "") { proxy.insertMermaid(type: "gantt") },
            Command(title: "Mermaid Pie Chart",    keywords: ["mermaid","pie","chart"],     shortcut: "") { proxy.insertMermaid(type: "pie") },
            Command(title: "Mermaid Class Diagram",keywords: ["mermaid","class","uml"],     shortcut: "") { proxy.insertMermaid(type: "class") },
        ])
    }
}

// MARK: - DividerHandle

/// Apple-style resizable panel divider with a pill grip indicator.
private struct DividerHandle: View {
    @State private var isHovered = false

    var body: some View {
        ZStack {
            // Hairline separator
            Color(.separatorColor)
                .frame(width: 1)

            // Pill grip
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

// MARK: - Global mode shortcuts

extension Notification.Name {
    static let setViewMode      = Notification.Name("com.truemarkdown.setViewMode")
    static let changeFontSize   = Notification.Name("com.truemarkdown.changeFontSize")
    static let toggleSearch     = Notification.Name("com.truemarkdown.toggleSearch")
    static let findNext         = Notification.Name("com.truemarkdown.findNext")
    static let findPrevious     = Notification.Name("com.truemarkdown.findPrevious")
    static let startScreenShouldClose = Notification.Name("com.truemarkdown.startScreenShouldClose")

}

struct TrueMarkdownCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Commands {
        // Store window actions early so non-SwiftUI code can open/close windows.
        let _: Void = {
            AppCoordinator.shared.openWindow = openWindow
            AppCoordinator.shared.dismissWindow = dismissWindow
            // If AppDelegate requested start screen before we were ready, open it now.
            if AppCoordinator.shared.pendingStartScreen {
                AppCoordinator.shared.pendingStartScreen = false
                openWindow(id: "start-screen")
            }
        }()

        CommandGroup(after: .newItem) {
            Button("Open Folder…") {
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
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Edit Mode") {
                NotificationCenter.default.post(name: .setViewMode, object: ViewMode.edit.rawValue)
            }.keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Preview Mode") {
                NotificationCenter.default.post(name: .setViewMode, object: ViewMode.preview.rawValue)
            }.keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Dual Mode") {
                NotificationCenter.default.post(name: .setViewMode, object: ViewMode.dual.rawValue)
            }.keyboardShortcut("d", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textFormatting) {
            Divider()
            Button("Increase Font Size") {
                NotificationCenter.default.post(name: .changeFontSize, object: 1.0)
            }.keyboardShortcut("+", modifiers: [.command])

            Button("Decrease Font Size") {
                NotificationCenter.default.post(name: .changeFontSize, object: -1.0)
            }.keyboardShortcut("-", modifiers: [.command])

            Button("Reset Font Size") {
                NotificationCenter.default.post(name: .changeFontSize, object: 0.0)
            }.keyboardShortcut("0", modifiers: [.command])
        }

        // ── Find ──────────────────────────────────────────────────────────
        CommandGroup(after: .textEditing) {
            Button("Find…") {
                NotificationCenter.default.post(name: .toggleSearch, object: nil)
            }.keyboardShortcut("f")

            Button("Find Next") {
                NotificationCenter.default.post(name: .findNext, object: nil)
            }.keyboardShortcut("g")

            Button("Find Previous") {
                NotificationCenter.default.post(name: .findPrevious, object: nil)
            }.keyboardShortcut("g", modifiers: [.command, .shift])
        }
    }
}
