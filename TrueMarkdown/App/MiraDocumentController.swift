import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - TrueMarkdownDocumentController

/// Custom document controller that allows selecting folders (in addition to markdown files)
/// from the standard "Open…" dialog. When a folder is chosen, it opens the folder-browser window.
final class TrueMarkdownDocumentController: NSDocumentController {

    /// Configure the panel to accept both .md files and folders, then run it synchronously.
    /// We bypass `super` because super reconfigures `allowedContentTypes` internally, which
    /// resets `canChooseDirectories = false` on macOS 14+.
    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        // Suppress any open panel triggered by DocumentGroup during startup.
        guard SessionManager.shared.restorationAttempted else {
            return NSApplication.ModalResponse.cancel.rawValue
        }
        configurePanel(openPanel)
        return openPanel.runModal().rawValue
    }

    /// Async variant — same bypass strategy as `runModalOpenPanel`.
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?, completionHandler: @escaping (Int) -> Void) {
        guard SessionManager.shared.restorationAttempted else {
            completionHandler(NSApplication.ModalResponse.cancel.rawValue)
            return
        }
        configurePanel(openPanel)
        openPanel.begin { [weak self] response in
            if response == .OK {
                for url in openPanel.urls {
                    self?.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                }
            }
            completionHandler(response.rawValue)
        }
    }

    private func configurePanel(_ openPanel: NSOpenPanel) {
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        // Show both .md files and folders; do NOT restrict to a content type list
        // because NSOpenPanel on macOS 14+ disables the Open button for items that
        // don't match allowedContentTypes even when canChooseDirectories = true.
        openPanel.allowedContentTypes = []
    }

    /// Intercept all "Open…" requests (File > Open, ⌘O, startup) so the panel
    /// always allows choosing both files and folders.
    @IBAction override func openDocument(_ sender: Any?) {
        guard SessionManager.shared.restorationAttempted else { return }
        let panel = NSOpenPanel()
        configurePanel(panel)
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                self?.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
        }
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue {
            SessionManager.shared.trackOpen(url: url, type: .folder)
            DispatchQueue.main.async {
                if let action = AppCoordinator.shared.openWindow {
                    action(id: "folder-browser", value: url)
                } else {
                    AppCoordinator.shared.pendingFolderURL = url
                    NotificationCenter.default.post(name: .openFolderURL, object: url)
                }
            }
            completionHandler(nil, false, nil)
        } else {
            SessionManager.shared.trackOpen(url: url, type: .file)
            super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
        }
    }
}

extension Notification.Name {
    static let openFolderURL = Notification.Name("com.truemarkdown.openFolderURL")
}
