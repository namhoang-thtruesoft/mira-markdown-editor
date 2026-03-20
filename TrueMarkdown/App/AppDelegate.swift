import AppKit
#if DIRECT_DOWNLOAD
import Sparkle
#endif

class AppDelegate: NSObject, NSApplicationDelegate {
    // TrueMarkdownDocumentController is stored here to keep a strong reference.
    // Initialized in applicationWillFinishLaunching so it becomes NSDocumentController.shared
    // before DocumentGroup registers its own controller.
    private var documentController: TrueMarkdownDocumentController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        documentController = TrueMarkdownDocumentController()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        #if DIRECT_DOWNLOAD
        AppUpdateManager.shared.startUpdater()
        #endif

        // Attempt session restoration or show start screen.
        // Deferred to next run-loop so SwiftUI scenes have a chance to register.
        DispatchQueue.main.async {
            self.restoreSessionOrShowStartScreen()
        }
    }

    // Prevent DocumentGroup from showing its own file picker on launch
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    // When the user clicks the dock icon with no windows, show start screen
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            DispatchQueue.main.async {
                if let action = AppCoordinator.shared.openWindow {
                    action(id: "start-screen")
                }
            }
            return false
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Session saving reserved for future use
    }

    // Called when Finder opens a file/folder via the Dock or Finder
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            SessionManager.shared.trackOpen(url: url, type: .folder)
            AppCoordinator.shared.pendingFolderURL = url
            NotificationCenter.default.post(name: .openFolderURL, object: url)
            return true
        }
        SessionManager.shared.trackOpen(url: url, type: .file)
        return false // let DocumentGroup handle files
    }

    // MARK: - Session Restoration

    @MainActor private func restoreSessionOrShowStartScreen() {
        SessionManager.shared.restorationAttempted = true
        showStartScreen()
    }

    @MainActor private func showStartScreen() {
        if let action = AppCoordinator.shared.openWindow {
            action(id: "start-screen")
        } else {
            // openWindow not yet available — TrueMarkdownCommands will pick this up
            AppCoordinator.shared.pendingStartScreen = true
        }
    }


}
