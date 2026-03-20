import SwiftUI

// MARK: - ImageInsertPanel
//
// Panel for inserting images into the Markdown editor.
// Supports URL input and local file selection.

struct ImageInsertPanel: View {
    @Binding var isPresented: Bool
    let onInsert: (String) -> Void

    @State private var imageURL: String = ""
    @State private var altText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert Image")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Image URL or path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("https://example.com/image.png", text: $imageURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse…") {
                        pickFile()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Alt text (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Description of image", text: $altText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Insert") {
                    guard !imageURL.isEmpty else { return }
                    onInsert("![\(altText)](\(imageURL))")
                    isPresented = false
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(imageURL.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            imageURL = url.path
        }
    }
}
