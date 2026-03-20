import SwiftUI

// MARK: - Export Format

enum ExportFormat {
    case pdf, html, markdown, png
}

// MARK: - ToolbarView

struct ToolbarView: ToolbarContent {
    @Bindable var viewModeManager: ViewModeManager
    @Binding var showTOC: Bool
    var onExport: (ExportFormat) -> Void
    var actionProxy: EditorActionProxy?
    @Binding var showCommandPalette: Bool

    var body: some ToolbarContent {

        // ── Left (navigation area): Editor-context controls ──────────────────
        // Spatial proximity: these act on / show the left editor panel.
        ToolbarItemGroup(placement: .navigation) {

            // Command palette (⌘K — universal "command" shortcut, like VS Code)
            Button { showCommandPalette.toggle() } label: {
                Image(systemName: "command.square")
            }
            .help("Command Palette (⌘K)")
            .keyboardShortcut("k")
        }

        // ── Center: View mode picker ─────────────────────────────────────────
        ToolbarItem(placement: .principal) {
            Picker("View Mode", selection: Binding(
                get: { viewModeManager.mode },
                set: { viewModeManager.setMode($0) }
            )) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.systemImage)
                        .help(mode.label)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }

        // ── Right: Formatting + Insert + Export ──────────────────────────────
        ToolbarItemGroup(placement: .primaryAction) {

            // Edit-only context: hide formatting in pure preview mode
            if viewModeManager.mode != .preview {

                // Inline formatting — standard macOS text editor shortcuts
                Button { actionProxy?.insertBold() } label: {
                    Image(systemName: "bold")
                }
                .help("Bold (⌘B)")
                .keyboardShortcut("b")

                Button { actionProxy?.insertItalic() } label: {
                    Image(systemName: "italic")
                }
                .help("Italic (⌘I)")
                .keyboardShortcut("i")

                Button { actionProxy?.insertInlineCode() } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .help("Inline Code (⌘⌥C)")
                .keyboardShortcut("c", modifiers: [.command, .option])

                // ── Insert ▾ — unified overflow menu with shortcuts ─────────────
                Menu {
                    Section("Heading") {
                        // ⌘⌥1–6 mirrors heading level — semantic and meMirable
                        ForEach(1...6, id: \.self) { level in
                            Button("Heading \(level)") { actionProxy?.insertHeading(level) }
                                .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: [.command, .option])
                        }
                    }

                    Divider()

                    Section("Inline") {
                        Button { actionProxy?.insertLink() } label: {
                            Label("Link", systemImage: "link")
                        }
                        .keyboardShortcut("l", modifiers: [.command, .option])

                        Button { actionProxy?.insertInlineCode() } label: {
                            Label("Inline Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .keyboardShortcut("c", modifiers: [.command, .option])

                        Button { actionProxy?.insertStrikethrough() } label: {
                            Label("Strikethrough", systemImage: "strikethrough")
                        }
                        .keyboardShortcut("x", modifiers: [.command, .option])
                    }

                    Divider()

                    Section("Block") {
                        Button { actionProxy?.insertCodeBlock() } label: {
                            Label("Code Block", systemImage: "terminal")
                        }
                        .keyboardShortcut("k", modifiers: [.command, .option])

                        Button { actionProxy?.insertBlockquote() } label: {
                            Label("Blockquote", systemImage: "text.quote")
                        }
                        .keyboardShortcut("q", modifiers: [.command, .option])

                        Button { actionProxy?.insertTable() } label: {
                            Label("Table", systemImage: "tablecells")
                        }
                        .keyboardShortcut("t", modifiers: [.command, .option])

                        Button { actionProxy?.insertImage() } label: {
                            Label("Image", systemImage: "photo")
                        }
                        .keyboardShortcut("p", modifiers: [.command, .option])

                        Button { actionProxy?.insertHorizontalRule() } label: {
                            Label("Horizontal Rule", systemImage: "minus")
                        }
                        .keyboardShortcut("h", modifiers: [.command, .option])
                    }

                    Divider()

                    Section("Mermaid Diagram") {
                        Button("Flowchart")     { actionProxy?.insertMermaid(type: "flowchart") }
                        Button("Sequence")      { actionProxy?.insertMermaid(type: "sequence") }
                        Button("Gantt Chart")   { actionProxy?.insertMermaid(type: "gantt") }
                        Button("Pie Chart")     { actionProxy?.insertMermaid(type: "pie") }
                        Button("Class Diagram") { actionProxy?.insertMermaid(type: "class") }
                    }
                } label: {
                    Label("Insert", systemImage: "plus")
                }
                .help("Insert Element")

            } // end if mode != .preview

            // TOC toggle (⌘⇧L — L for List/right-panel)
            Button { showTOC.toggle() } label: {
                Image(systemName: "sidebar.right")
                    .symbolVariant(showTOC ? .fill : .none)
            }
            .help("Toggle Table of Contents (⌘⇧L)")
            .keyboardShortcut("l", modifiers: [.command, .shift])

            // Export — document-level, correctly at far right
            Menu {
                Button("Export as PDF")     { onExport(.pdf) }
                Button("Export as HTML")    { onExport(.html) }
                Button("Copy Markdown")     { onExport(.markdown) }
                Button("Export as PNG")     { onExport(.png) }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Share / Export (⌘⌥S)")
            .keyboardShortcut("s", modifiers: [.command, .option])
        }
    }
}
