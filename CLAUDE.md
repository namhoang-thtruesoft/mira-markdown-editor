# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

True Markdown is a native macOS Markdown Editor built with Swift/SwiftUI targeting macOS 14.0+. It uses a document-based app pattern with live preview rendering via WKWebView.

## Build System

The project uses **XcodeGen** to generate the `.xcodeproj` from `project.yml`, plus Swift Package Manager for dependencies.

```bash
# Regenerate Xcode project after modifying project.yml
xcodegen generate

# Build
xcodebuild build -scheme "True Markdown (AppStore)"
xcodebuild build -scheme "True Markdown (Direct)"

# Run all tests
xcodebuild test -scheme "True Markdown (AppStore)"

# Run a single test suite or test by name
xcodebuild test -scheme "True Markdown (AppStore)" -only-testing:TrueMarkdownTests/MarkdownParserTests
xcodebuild test -scheme "True Markdown (AppStore)" -only-testing:TrueMarkdownTests/MarkdownParserTests/parseHeading
```

Tests use **Swift Testing** (`@Suite`, `@Test`, `#expect`) — not XCTest. The test target imports `@testable import TrueMarkdownAppStore`.

There are two build schemes:
- **True Markdown (AppStore)** — Mac App Store distribution, bundle ID `com.thtruesoft.truemarkdown`
- **True Markdown (Direct)** — Direct download with Sparkle auto-updater and Pandoc import; uses `DIRECT_DOWNLOAD` compile flag

## Architecture

### App Entry Points (`TrueMarkdown/App/`)

`MiraApp.swift` defines two SwiftUI scenes:
1. **`DocumentGroup`** — Standard document-based scene; opens `.md` files via `ContentView`
2. **`WindowGroup("folder-browser")`** — Folder browser scene; opens via `FolderWindowView`

`AppDelegate` holds a strong reference to `TrueMarkdownDocumentController` (must be initialized before `DocumentGroup` registers its own controller) and starts the Sparkle updater in Direct builds.

`TrueMarkdownDocumentController` customizes `NSDocumentController` to support opening folders via drag-and-drop and Finder, posting a `.openFolderURL` notification that the window scenes observe.

### Core Engine (`TrueMarkdown/Core/`)
- `MarkdownEngine/MarkdownParser.swift` — Parses markdown to AST using Apple's `swift-markdown` library
- `MarkdownEngine/HTMLRenderer.swift` — Renders AST to HTML, assigning block IDs for incremental updates
- `MarkdownEngine/IncrementalRenderer.swift` — Diffs and patches specific HTML blocks (BlockPatch system) for performance
- `Models/MiraDocument.swift` — `FileDocument` conformance for `.md` files; type is `TrueMarkdownDocument`
- `Models/DocumentState.swift` — Per-document UI state persisted via UserDefaults
- `ImageAssetManager.swift` — Copies images into a companion `<docname>-assets/` folder and returns relative paths

### Features (`TrueMarkdown/Features/`)
- **Editor** — NSTextView-based raw markdown editing with slash commands and image insertion
- **Preview** — WKWebView live HTML rendering; `ViewModeManager` handles edit/preview/dual modes
- **TOC** — Extracts headings and renders a right-side table of contents panel
- **FolderBrowser** — `FolderWindowView` + `FolderWindowManager` + `FolderBrowserView`/`FileNode` for a folder-mode window with a file-tree sidebar
- **CommandPalette** — Cmd+K launcher backed by `CommandRegistry`; commands are registered in `ContentView.registerCommands()`
- **Search** — Find/replace with `SearchState`; operates on both editor (via `EditorActionProxy`) and preview (via `WKWebView.evaluateJavaScript`)
- **Export** — HTML/PDF/PNG export via `ExportManager`

### EditorActionProxy

`EditorActionProxy` is the bridge between the toolbar/command palette and the underlying `NSTextView`. It holds a `weak var textView` set by `EditorView`, and exposes all text-manipulation methods (`insertBold`, `insertHeading`, `highlightMatches`, etc.). Both `ContentView` and `FolderWindowView` own an instance and pass it to `ToolbarView` and the editor.

### Resources
- `Resources/preview-template.html` — The HTML shell for the preview pane; includes KaTeX, Mermaid.js, and ECharts integrations
- `Resources/katex/` — Bundled KaTeX fonts for offline math rendering
- `Resources/mermaid.min.js` / `echarts.min.js` — Bundled diagram/chart libraries

### Distribution-specific
- `Targets/Direct/AppUpdateManager.swift` — Sparkle auto-updater, only compiled when `DIRECT_DOWNLOAD` is set
- `Targets/AppStore/` and `Targets/Direct/` — Separate entitlements and Info.plist per distribution

## Key Design Patterns

- **Incremental rendering**: The editor sends diffs to the preview using a BlockPatch system rather than re-rendering the entire document on each keystroke. Render is debounced 100ms on keystrokes; immediate on first appear.
- **Always-alive views**: Both `EditorView` and `PreviewView` are always in the hierarchy; visibility is controlled by `.opacity` and `.allowsHitTesting` to avoid WKWebView recreation cost.
- **Inter-component communication**: View mode changes, font size changes, search toggles, and folder-open requests all flow through `NotificationCenter` (see `Notification.Name` extensions in `ContentView.swift`). This decouples menu commands from view state.
- **Feature flags**: `Core/FeatureFlags.swift` contains compile-time toggles; `DIRECT_DOWNLOAD` guards Sparkle/Pandoc features.
- **Document state**: Per-document preferences (view mode, TOC visibility) are stored in UserDefaults keyed by document identity, not in the `.md` file itself.

## Dependencies (Swift Package Manager)

- `swift-markdown` (Apple, v0.4.0+) — Markdown AST parsing
- `Sparkle` (v2.6.0+) — Auto-updater, Direct build only
