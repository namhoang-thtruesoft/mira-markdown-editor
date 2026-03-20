import Foundation

/// Sparkle auto-updater — Direct Download build only.
#if DIRECT_DOWNLOAD
import Sparkle

@MainActor
final class AppUpdateManager {
    static let shared = AppUpdateManager()

    private let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func startUpdater() {
        updaterController.startUpdater()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
#endif
