import Foundation

// MARK: - RecentItem

/// Represents a recently-opened item (file or folder).
struct RecentItem: Codable, Identifiable, Equatable {
    enum ItemType: String, Codable {
        case file
        case folder
    }

    let url: URL
    let type: ItemType
    var lastOpened: Date

    var id: URL { url }

    /// Display name derived from the URL's last path component.
    var displayName: String { url.lastPathComponent }

    /// Parent path for subtitle display, abbreviated with ~.
    var parentPath: String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Whether the file/folder still exists on disk.
    var isAccessible: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

// MARK: - SessionManager

/// Manages session persistence and recent item history.
@MainActor @Observable
final class SessionManager {
    static let shared = SessionManager()
    private init() { load() }

    /// Items that were open when the app last quit — used for restoration.
    private(set) var lastSession: [RecentItem] = []

    /// Full recent history (files + folders), most recent first.
    private(set) var recentHistory: [RecentItem] = []

    /// Whether session restoration has been attempted this launch.
    var restorationAttempted: Bool = false

    private let sessionKey = "truemarkdown.activeSession"
    private let historyKey = "truemarkdown.recentHistory"
    private let maxHistory = 20

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let items = try? JSONDecoder().decode([RecentItem].self, from: data) {
            lastSession = items.filter(\.isAccessible)
        }
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let items = try? JSONDecoder().decode([RecentItem].self, from: data) {
            recentHistory = items.filter(\.isAccessible)
        }
    }

    private func saveSession(_ items: [RecentItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(recentHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    // MARK: - Session Tracking

    /// Call when a file or folder is opened. Adds to history.
    func trackOpen(url: URL, type: RecentItem.ItemType) {
        let item = RecentItem(url: url, type: type, lastOpened: Date())

        // Move to front if already present
        recentHistory.removeAll { $0.url == url }
        recentHistory.insert(item, at: 0)
        if recentHistory.count > maxHistory {
            recentHistory = Array(recentHistory.prefix(maxHistory))
        }
        saveHistory()
    }

    /// Snapshot the currently-open items for session restoration.
    /// Called on applicationWillTerminate.
    func saveActiveSession(fileURLs: [URL], folderURLs: [URL]) {
        var items: [RecentItem] = []
        for url in fileURLs {
            items.append(RecentItem(url: url, type: .file, lastOpened: Date()))
        }
        for url in folderURLs {
            items.append(RecentItem(url: url, type: .folder, lastOpened: Date()))
        }
        saveSession(items)
    }

    /// Clear the saved session (after successful restoration).
    func clearSavedSession() {
        lastSession = []
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    /// Remove a single item from recent history.
    func removeFromHistory(url: URL) {
        recentHistory.removeAll { $0.url == url }
        saveHistory()
    }

    /// Clear all recent history.
    func clearHistory() {
        recentHistory = []
        saveHistory()
    }
}
