import AppKit
import SwiftUI

// MARK: - SelectionToolbarPanel
// A lightweight NSPanel that floats above the text selection in NSTextView
// and offers quick Bold / Italic / Code / Link formatting buttons.

@MainActor
final class SelectionToolbarPanel: NSObject {

    // MARK: - State
    private var panel: NSPanel?
    private weak var textView: NSTextView?
    private var actionProxy: EditorActionProxy?

    // MARK: - Init
    init(textView: NSTextView, actionProxy: EditorActionProxy?) {
        self.textView = textView
        self.actionProxy = actionProxy
        super.init()
    }

    // MARK: - Show / Hide

    func showIfNeeded() {
        guard let textView,
              let window = textView.window,
              !textView.selectedRange().length.isZero else {
            hide()
            return
        }

        let rect = selectionRect(in: textView, window: window)
        guard let rect else { hide(); return }

        if panel == nil { panel = makePanel() }
        guard let panel else { return }

        // Position panel above selection, centred horizontally
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: rect.midX - panelSize.width / 2,
            y: rect.maxY + 10          // 10px above selection top
        )

        panel.setFrameOrigin(origin)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - Panel Construction

    private func makePanel() -> NSPanel {
        let hostingView = NSHostingView(rootView: selectionToolbarView())

        // Size to fit the SwiftUI content
        let fittingSize = hostingView.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        return panel
    }

    @ViewBuilder
    private func selectionToolbarView() -> some View {
        HStack(spacing: 0) {
            // Inline formatting group
            selectionButton("bold",    "Bold (⌘B)")       { self.actionProxy?.insertBold() }
            selectionButton("italic",  "Italic (⌘I)")     { self.actionProxy?.insertItalic() }
            selectionButton("chevron.left.forwardslash.chevron.right", "Inline Code (⌘⌥C)") {
                self.actionProxy?.insertInlineCode()
            }

            // Divider between groups
            Divider()
                .frame(height: 18)
                .padding(.horizontal, 4)

            selectionButton("link", "Link") { self.actionProxy?.insertLink() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
    }

    private func selectionButton(_ icon: String, _ tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(SelectionButtonStyle())
        .help(tooltip)
    }

    // MARK: - Helpers

    private func selectionRect(in textView: NSTextView, window: NSWindow) -> NSRect? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }
        let range = textView.selectedRange()
        guard range.length > 0 else { return nil }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        // Convert from text container coords → view → window → screen
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        let viewRect = textView.convert(rect, to: nil)
        return window.convertToScreen(viewRect)
    }
}

// MARK: - SelectionButtonStyle

private struct SelectionButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered || configuration.isPressed ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed
                          ? Color.accentColor.opacity(0.15)
                          : isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Convenience extension on Int
private extension Int {
    var isZero: Bool { self == 0 }
}
