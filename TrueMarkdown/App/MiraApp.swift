import SwiftUI

@main
struct TrueMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // ── Standard document (file) scene ──────────────────────────────────
        DocumentGroup(newDocument: TrueMarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            TrueMarkdownCommands()
        }

        // ── Folder browser scene ─────────────────────────────────────────────
        WindowGroup("Folder", id: "folder-browser", for: URL.self) { $url in
            if let folderURL = url {
                FolderWindowView(folderURL: folderURL)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .handlesExternalEvents(matching: [])

        // ── Start screen (single instance) ───────────────────────────────
        Window("Welcome to True Markdown", id: "start-screen") {
            StartScreenView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
        }
    }
}
