import Foundation
import AppKit

// MARK: - Command

struct Command: Identifiable {
    let id = UUID()
    let title: String
    let keywords: [String]
    let shortcut: String
    let action: @MainActor () -> Void

    /// Fuzzy-score: returns a score > 0 if the query matches this command.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        let searchTarget = (title + " " + keywords.joined(separator: " ")).lowercased()
        return searchTarget.contains(q)
    }
}

// MARK: - CommandRegistry

@MainActor
final class CommandRegistry: ObservableObject {
    static let shared = CommandRegistry()

    @Published private(set) var commands: [Command] = []

    private init() {}

    func register(_ command: Command) {
        commands.append(command)
    }

    func register(contentsOf newCommands: [Command]) {
        commands.append(contentsOf: newCommands)
    }

    func results(for query: String) -> [Command] {
        query.isEmpty ? commands : commands.filter { $0.matches(query) }
    }
}
