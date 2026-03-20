import Foundation
import SwiftUI

/// Shared coordinator for app-level state that needs to survive across
/// SwiftUI scene transitions (e.g. a folder URL selected before any view is alive).
@Observable
@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()
    private init() {}

    /// A folder URL that was selected before a ContentView existed to receive
    /// the openFolderURL notification. Consumed by the first ContentView that appears.
    var pendingFolderURL: URL? = nil

    /// Stored early from TrueMarkdownCommands so non-SwiftUI code (e.g. TrueMarkdownDocumentController)
    /// can open the folder-browser window before any ContentView exists.
    var openWindow: OpenWindowAction? = nil

    /// Stored from TrueMarkdownCommands so non-SwiftUI code can dismiss the start screen.
    var dismissWindow: DismissWindowAction? = nil

    /// Set to true when session restoration or start screen should happen
    /// but openWindow isn't available yet. TrueMarkdownCommands consumes this.
    var pendingStartScreen: Bool = false

    /// Tracks currently-open folder URLs for session saving.
    /// FolderWindowView registers on appear, unregisters on disappear.
    var openFolderURLs: [URL] = []

    func registerFolder(_ url: URL) {
        if !openFolderURLs.contains(url) {
            openFolderURLs.append(url)
        }
    }

    func unregisterFolder(_ url: URL) {
        openFolderURLs.removeAll { $0 == url }
    }
}
