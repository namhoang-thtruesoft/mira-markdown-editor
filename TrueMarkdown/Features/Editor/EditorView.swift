import SwiftUI
import AppKit
import Combine

// MARK: - EditorView

/// NSTextView-backed editor for raw Markdown input.
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 15
    var actionProxy: EditorActionProxy? = nil   // ← receives toolbar/palette actions

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 24, height: 28)
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.drawsBackground = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        context.coordinator.textView = textView
        actionProxy?.textView = textView

        // Overlay-style scrollbar (thin, auto-hides)
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        // Wire up Option B (selection toolbar) and Option D (slash commands)
        context.coordinator.setupFloatingFeatures(textView: textView, actionProxy: actionProxy)


        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let range = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = range
        }
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Keep proxy up to date if view is recreated
        actionProxy?.textView = textView
        context.coordinator.actionProxy = actionProxy
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(binding: $text)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var binding: Binding<String>
        weak var textView: NSTextView?
        var actionProxy: EditorActionProxy?

        // Option B
        private var selectionToolbar: SelectionToolbarPanel?
        // Option D
        private var slashCommand: SlashCommandController?

        init(binding: Binding<String>) {
            self.binding = binding
        }

        func setupFloatingFeatures(textView: NSTextView, actionProxy: EditorActionProxy?) {
            self.actionProxy = actionProxy
            self.selectionToolbar = SelectionToolbarPanel(textView: textView, actionProxy: actionProxy)
            self.slashCommand = SlashCommandController(textView: textView, actionProxy: actionProxy)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            binding.wrappedValue = tv.string
            // Hide selection bar when typing
            selectionToolbar?.hide()
            // Check for slash trigger
            slashCommand?.textDidChange(in: tv)
        }


        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            selectionToolbar?.showIfNeeded()
            // Let the slash controller decide whether to stay visible based on cursor position
            slashCommand?.selectionDidChange(in: tv)
        }

        /// Scroll editor to a character offset (called by TOC).
        func scrollTo(characterIndex: Int) {
            guard let tv = textView else { return }
            let range = NSRange(location: min(characterIndex, tv.string.count), length: 0)
            tv.scrollRangeToVisible(range)
            tv.setSelectedRange(range)
        }
    }
}
