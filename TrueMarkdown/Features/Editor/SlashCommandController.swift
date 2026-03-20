#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Slash Command Item

struct SlashCommandItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let action: (EditorActionProxy) -> Void
}

// MARK: - SlashCommandController
// Detects when the user types "/" at the beginning of a new line and
// shows a fuzzy-filtered popup list of insertable Markdown elements.

@MainActor
final class SlashCommandController: NSObject {

    // MARK: - Properties
    private weak var textView: NSTextView?
    private var actionProxy: EditorActionProxy?
    private var panel: NSPanel?
    private var hostingController: NSHostingController<SlashMenuView>?

    private var triggerRange: NSRange?   // range of the "/" char that opened the menu
    private var filterText: String = ""
    private var mouseMonitor: Any? = nil  // NSEvent outside-click monitor

    // ── All available commands ─────────────────────────────────────────────
    private static let allCommands: [SlashCommandItem] = [
        SlashCommandItem(title: "Heading 1",    subtitle: "# Large heading",           icon: "textformat.size.larger") { $0.insertHeading(1) },
        SlashCommandItem(title: "Heading 2",    subtitle: "## Medium heading",          icon: "textformat.size") { $0.insertHeading(2) },
        SlashCommandItem(title: "Heading 3",    subtitle: "### Small heading",          icon: "textformat.size.smaller") { $0.insertHeading(3) },
        SlashCommandItem(title: "Bold",         subtitle: "**bold text**",             icon: "bold") { $0.insertBold() },
        SlashCommandItem(title: "Italic",       subtitle: "*italic text*",             icon: "italic") { $0.insertItalic() },
        SlashCommandItem(title: "Inline Code",  subtitle: "`code`",                   icon: "chevron.left.forwardslash.chevron.right") { $0.insertInlineCode() },
        SlashCommandItem(title: "Link",         subtitle: "[text](url)",              icon: "link") { $0.insertLink() },
        SlashCommandItem(title: "Image",        subtitle: "![alt](url)",              icon: "photo") { $0.insertImage() },
        SlashCommandItem(title: "Table",        subtitle: "Insert a Markdown table",  icon: "tablecells") { $0.insertTable() },
        SlashCommandItem(title: "Flowchart",    subtitle: "Mermaid flowchart",        icon: "arrow.triangle.branch") { $0.insertMermaid(type: "flowchart") },
        SlashCommandItem(title: "Sequence",     subtitle: "Mermaid sequence diagram", icon: "arrow.left.arrow.right") { $0.insertMermaid(type: "sequence") },
        SlashCommandItem(title: "Gantt Chart",  subtitle: "Mermaid gantt chart",      icon: "calendar") { $0.insertMermaid(type: "gantt") },
        SlashCommandItem(title: "Pie Chart",    subtitle: "Mermaid pie chart",        icon: "chart.pie") { $0.insertMermaid(type: "pie") },
        SlashCommandItem(title: "Class Diagram",subtitle: "Mermaid class diagram",    icon: "square.3.layers.3d") { $0.insertMermaid(type: "class") },
    ]

    // MARK: - Init
    init(textView: NSTextView, actionProxy: EditorActionProxy?) {
        self.textView = textView
        self.actionProxy = actionProxy
        super.init()
    }

    // MARK: - Text Change Handler

    func textDidChange(in textView: NSTextView) {
        let text = textView.string
        let selectedRange = textView.selectedRange()
        guard selectedRange.location != NSNotFound else { return }

        let cursorPos = selectedRange.location

        // Find start of current line
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
        let lineStart = lineRange.location

        // Text from line start to cursor
        let textBeforeCursor = nsText.substring(with: NSRange(location: lineStart, length: cursorPos - lineStart))

        if let slashIdx = textBeforeCursor.firstIndex(of: "/") {
            // The "/" must be the first non-whitespace character on the line
            let beforeSlash = String(textBeforeCursor[textBeforeCursor.startIndex..<slashIdx])
            if beforeSlash.trimmingCharacters(in: .whitespaces).isEmpty {
                filterText = String(textBeforeCursor[textBeforeCursor.index(after: slashIdx)...])
                let slashCharPos = lineStart + beforeSlash.count
                triggerRange = NSRange(location: slashCharPos, length: cursorPos - slashCharPos)
                showMenu(near: selectedRange)
                return
            }
        }

        hide()
    }

    func hide() {
        panel?.orderOut(nil)
        triggerRange = nil
        filterText = ""
        // Remove the outside-click monitor
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    // MARK: - Selection Change (cursor moved in editor)

    /// Called by the coordinator on every selection change.
    /// Hides the menu if the cursor is no longer immediately after a `/` at line start.
    func selectionDidChange(in textView: NSTextView) {
        guard panel?.isVisible == true else { return }
        let text = textView.string
        let cursorPos = textView.selectedRange().location
        guard cursorPos != NSNotFound else { hide(); return }

        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
        let lineStart = lineRange.location
        let textBeforeCursor = nsText.substring(with: NSRange(location: lineStart,
                                                              length: cursorPos - lineStart))

        // Keep visible only if cursor is still after a "/" that is the first non-whitespace
        if let slashIdx = textBeforeCursor.firstIndex(of: "/") {
            let beforeSlash = String(textBeforeCursor[textBeforeCursor.startIndex..<slashIdx])
            if beforeSlash.trimmingCharacters(in: .whitespaces).isEmpty {
                // Still in slash context — update filter if text changed
                let newFilter = String(textBeforeCursor[textBeforeCursor.index(after: slashIdx)...])
                if newFilter != filterText {
                    filterText = newFilter
                    showMenu(near: textView.selectedRange())
                }
                return
            }
        }
        hide()
    }


    // MARK: - Menu

    private func showMenu(near range: NSRange) {
        let filtered = filteredItems()
        guard !filtered.isEmpty else { hide(); return }

        let origin = cursorScreenPoint() ?? NSPoint(x: 400, y: 400)

        if panel == nil { panel = makePanel() }
        updateContent(filtered)

        let panelHeight = min(CGFloat(filtered.count) * 52 + 16, 320)
        let panelFrame = NSRect(x: origin.x, y: origin.y - panelHeight - 4,
                                width: 300, height: panelHeight)
        panel?.setFrame(panelFrame, display: true)

        let wasHidden = panel?.isVisible == false
        if wasHidden { panel?.orderFront(nil) }

        // Register a one-shot outside-click monitor when panel first appears
        if wasHidden, mouseMonitor == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let p = self.panel, p.isVisible else { return event }
                let clickPoint = event.locationInWindow
                let screenPoint = event.window?.convertToScreen(NSRect(origin: clickPoint, size: .zero)).origin
                    ?? NSPoint(x: clickPoint.x, y: clickPoint.y)
                if !p.frame.contains(screenPoint) {
                    self.hide()
                }
                return event
            }
        }
    }

    private func filteredItems() -> [SlashCommandItem] {
        if filterText.isEmpty { return SlashCommandController.allCommands }
        let lower = filterText.lowercased()
        return SlashCommandController.allCommands.filter {
            $0.title.lowercased().contains(lower) || $0.subtitle.lowercased().contains(lower)
        }
    }

    private func makePanel() -> NSPanel {
        let view = SlashMenuView(items: [], onSelect: { [weak self] item in
            self?.commit(item: item)
        })
        let hc = NSHostingController(rootView: view)
        self.hostingController = hc

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hc.view
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func updateContent(_ items: [SlashCommandItem]) {
        hostingController?.rootView = SlashMenuView(items: items, onSelect: { [weak self] item in
            self?.commit(item: item)
        })
    }

    private func commit(item: SlashCommandItem) {
        guard let textView, let proxy = actionProxy, let trigger = triggerRange else { return }
        // Delete the typed "/text" before inserting
        textView.insertText("", replacementRange: trigger)
        item.action(proxy)
        hide()
    }

    // MARK: - Helpers

    private func cursorScreenPoint() -> NSPoint? {
        guard let textView, let window = textView.window,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }

        let cursorPos = textView.selectedRange().location
        var glyph = layoutManager.glyphIndexForCharacter(at: min(cursorPos, textView.string.count))
        if glyph == NSNotFound { glyph = 0 }
        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        lineRect.origin.x += textView.textContainerOrigin.x
        lineRect.origin.y += textView.textContainerOrigin.y
        let viewPoint = textView.convert(lineRect.origin, to: nil)
        return window.convertToScreen(NSRect(origin: viewPoint, size: .zero)).origin
    }
}

// MARK: - Slash Menu SwiftUI View

struct SlashMenuView: View {
    var items: [SlashCommandItem]
    var onSelect: (SlashCommandItem) -> Void

    @State private var hoveredId: UUID? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .frame(width: 24, height: 24)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(item.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(hoveredId == item.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in hoveredId = inside ? item.id : nil }
                }
            }
            .padding(.vertical, 8)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}
#endif
