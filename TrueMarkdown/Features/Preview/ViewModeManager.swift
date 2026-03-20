import SwiftUI
import WebKit
import Combine

// MARK: - ViewMode

enum ViewMode: String, CaseIterable {
    case edit    = "edit"
    case preview = "preview"
    case dual    = "dual"

    var label: String {
        switch self {
        case .edit:    return "Edit"
        case .preview: return "Preview"
        case .dual:    return "Dual"
        }
    }

    var systemImage: String {
        switch self {
        case .edit:    return "pencil"
        case .preview: return "eye"
        case .dual:    return "rectangle.split.2x1"
        }
    }
}

// MARK: - ViewModeManager

/// Observable state for the current view mode, persisted per document.
@MainActor
@Observable
final class ViewModeManager {
    var mode: ViewMode = .dual

    private let storageKey: String

    init(documentURL: URL?) {
        let key = documentURL?.path ?? "default"
        self.storageKey = "viewMode-\(key.hashValue)"
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           let mode = ViewMode(rawValue: saved) {
            self.mode = mode
        }
    }

    func setMode(_ newMode: ViewMode) {
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: storageKey)
    }
}
