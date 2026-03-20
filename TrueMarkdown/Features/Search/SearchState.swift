import SwiftUI

// MARK: - SearchState

/// Observable search state shared between the editor and preview panels.
@MainActor
@Observable
final class SearchState {
    var query: String = ""
    var replacement: String = ""
    var caseSensitive: Bool = false
    var showReplace: Bool = false

    // Match tracking
    var matchCount: Int = 0
    var currentMatchIndex: Int = 0

    /// Human-readable match indicator, e.g. "3 of 12" or "No results".
    var matchLabel: String {
        if query.isEmpty { return "" }
        if matchCount == 0 { return "No results" }
        return "\(currentMatchIndex + 1) of \(matchCount)"
    }

    // MARK: - Navigation

    func nextMatch() {
        guard matchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchCount
    }

    func previousMatch() {
        guard matchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
    }

    func reset() {
        query = ""
        replacement = ""
        matchCount = 0
        currentMatchIndex = 0
    }
}
