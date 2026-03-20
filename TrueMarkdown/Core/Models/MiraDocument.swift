import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Markdown UTI resolved by file extension — no Info.plist declaration required.
    static let truemarkdown_markdown: UTType = UTType(filenameExtension: "md") ?? .plainText
}

/// The native document model for True Markdown (.md files).
struct TrueMarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.truemarkdown_markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.truemarkdown_markdown, .plainText] }

    var text: String

    init(text: String = "# Untitled\n\n") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return FileWrapper(regularFileWithContents: data)
    }
}
