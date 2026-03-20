import Foundation
import AppKit

// MARK: - DocumentState

/// Persists per-document UI state (view mode, TOC visibility, scroll).
/// Keyed by a stable hash of the document's file URL (or a fallback for unsaved docs).
final class DocumentState {
    private let key: String

    init(fileURL: URL?) {
        key = fileURL?.path.hashValue.description ?? "unsaved"
    }

    // MARK: - View Mode

    var viewMode: ViewMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "\(key).viewMode")
                ?? UserDefaults.standard.string(forKey: "defaultViewMode")
                ?? ViewMode.dual.rawValue
            return ViewMode(rawValue: raw) ?? .dual
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "\(key).viewMode") }
    }

    // MARK: - TOC Visibility

    var tocVisible: Bool {
        get {
            UserDefaults.standard.object(forKey: "\(key).tocVisible") as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: "\(key).tocVisible") }
    }
}
