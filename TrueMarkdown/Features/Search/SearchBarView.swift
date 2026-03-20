import SwiftUI

// MARK: - SearchBarView

/// Floating find bar with Apple Liquid Glass styling.
/// Positioned over the editor or preview panel by the parent view.
struct SearchBarView: View {
    @Bindable var searchState: SearchState
    @Binding var isVisible: Bool
    var onQueryChanged: () -> Void
    var onNavigate: () -> Void
    var onReplace: () -> Void
    var onReplaceAll: () -> Void
    var onDismiss: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            // ── Find row ──────────────────────────────────────────────────
            findRow

            // ── Replace row (expandable) ──────────────────────────────────
            if searchState.showReplace {
                replaceRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(LiquidGlassBackground())
        .onAppear { isSearchFieldFocused = true }
    }

    // MARK: - Find Row

    private var findRow: some View {
        HStack(spacing: 6) {
            // Search input capsule
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Find…", text: $searchState.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFieldFocused)
                    .onSubmit { searchState.nextMatch(); onNavigate() }
                    .onChange(of: searchState.query) { _, _ in onQueryChanged() }

                if !searchState.query.isEmpty {
                    Text(searchState.matchLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()

                    Button {
                        searchState.query = ""
                        onQueryChanged()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))

            // Navigation
            HStack(spacing: 2) {
                Button { searchState.previousMatch(); onNavigate() } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                }
                .help("Previous Match (⌘⇧G)")

                Button { searchState.nextMatch(); onNavigate() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .help("Next Match (⌘G)")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(searchState.matchCount == 0)

            // Case sensitivity
            Button {
                searchState.caseSensitive.toggle()
                onQueryChanged()
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(searchState.caseSensitive ? .primary : .secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Case Sensitive")

            // Toggle replace
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    searchState.showReplace.toggle()
                }
            } label: {
                Image(systemName: "arrow.2.squarepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(searchState.showReplace ? .primary : .secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Toggle Replace")

            Spacer()

            // Dismiss
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Close (Esc)")
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    // MARK: - Replace Row

    private var replaceRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.swap")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Replace…", text: $searchState.replacement)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { onReplace() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))

            Button("Replace") { onReplace() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(searchState.matchCount == 0)

            Button("All") { onReplaceAll() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(searchState.matchCount == 0)

            Spacer()
        }
    }
}

// MARK: - Liquid Glass Background Modifier

/// Applies `.glassEffect` on macOS 26+, falls back to `.ultraThinMaterial` on older systems.
private struct LiquidGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }
}
