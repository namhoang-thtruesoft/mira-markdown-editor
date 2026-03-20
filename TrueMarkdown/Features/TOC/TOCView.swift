import SwiftUI

// MARK: - TOCView

struct TOCView: View {
    let entries: [TOCEntry]
    let onSelect: (TOCEntry) -> Void

    @State private var hoveredID: String?

    var body: some View {
        List(entries) { entry in
            Button(action: { onSelect(entry) }) {
                HStack(spacing: 0) {
                    // Depth indicator line for deeper levels
                    if entry.level > 1 {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.25))
                            .frame(width: 1.5, height: 14)
                            .padding(.trailing, 6)
                    }

                    Text(entry.title)
                        .font(tocFont(for: entry.level))
                        .fontWeight(entry.level == 1 ? .semibold : .regular)
                        .foregroundStyle(entry.level == 1 ? .primary : .secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, CGFloat(max(0, entry.level - 1) * 10))
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredID == entry.id.uuidString
                          ? Color(.selectedContentBackgroundColor).opacity(0.45)
                          : Color.clear)
                    .padding(.horizontal, 2)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    hoveredID = hovering ? entry.id.uuidString : nil
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Contents")
    }

    // MARK: - Helpers

    private func tocFont(for level: Int) -> Font {
        switch level {
        case 1:  return .system(size: 13, weight: .semibold)
        case 2:  return .system(size: 12.5)
        default: return .system(size: 12)
        }
    }
}
