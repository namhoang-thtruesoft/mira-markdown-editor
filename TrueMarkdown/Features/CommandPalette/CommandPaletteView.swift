import SwiftUI
import AppKit

// MARK: - CommandPaletteView

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var hoveredIndex: Int? = nil
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // ── Search field ───────────────────────────────────────────────────
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 16)

                TextField("Search commands…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isSearchFocused)
                    .onSubmit { executeSelected() }

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider()
                .opacity(0.6)

            // ── Results ────────────────────────────────────────────────────────
            let results = CommandRegistry.shared.results(for: query)
            if results.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 13))
                    Text("No matching commands")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { idx, cmd in
                            CommandRow(
                                command: cmd,
                                isSelected: idx == selectedIndex,
                                isHovered: hoveredIndex == idx
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIndex = idx
                                executeSelected()
                            }
                            .onHover { hovering in
                                hoveredIndex = hovering ? idx : nil
                                if hovering { selectedIndex = idx }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 500)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 10)
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
        .onAppear { isSearchFocused = true; selectedIndex = 0 }
        .onChange(of: query) { _, _ in selectedIndex = 0; hoveredIndex = nil }
        .onKeyPress(.upArrow)   { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(+1); return .handled }
        .onKeyPress(.escape)    { isPresented = false; return .handled }
    }

    private func moveSelection(_ delta: Int) {
        let results = CommandRegistry.shared.results(for: query)
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    private func executeSelected() {
        let results = CommandRegistry.shared.results(for: query)
        guard results.indices.contains(selectedIndex) else { return }
        isPresented = false
        results[selectedIndex].action()
    }
}

// MARK: - CommandRow

private struct CommandRow: View {
    let command: Command
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(command.title)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .primary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !command.shortcut.isEmpty {
                Text(command.shortcut)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isSelected ? .secondary : .tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(.windowBackgroundColor).opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(.selectedContentBackgroundColor))
                        .padding(.horizontal, 6)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(.selectedContentBackgroundColor).opacity(0.4))
                        .padding(.horizontal, 6)
                } else {
                    Color.clear
                }
            }
        )
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}
