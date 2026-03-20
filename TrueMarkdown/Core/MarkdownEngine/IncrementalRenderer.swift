import Foundation
@preconcurrency import Markdown

// MARK: - Incremental Renderer

/// Tracks the previous render's block patches and emits only changed blocks.
@MainActor
final class IncrementalRenderer: ObservableObject {
    private var previousPatches: [String: String] = [:]   // blockId → html
    private var previousText: String = ""

    /// Processes new Markdown text and returns only changed `BlockPatch` objects.
    /// - Returns: Empty array if nothing changed.
    func diff(newText: String) -> [BlockPatch] {
        guard newText != previousText else { return [] }
        previousText = newText

        let document = MarkdownParser.parse(newText)
        let newPatches = HTMLRenderer.renderBlocks(document)

        var changed: [BlockPatch] = []
        var newMap: [String: String] = [:]
        for patch in newPatches {
            newMap[patch.blockId] = patch.html
            if previousPatches[patch.blockId] != patch.html {
                changed.append(patch)
            }
        }

        // Detect removed blocks (blockId present in previous but not new)
        let removedIds = Set(previousPatches.keys).subtracting(newMap.keys)
        for id in removedIds {
            changed.append(BlockPatch(blockId: id, html: ""))
        }

        previousPatches = newMap
        return changed
    }

    /// Resets state — use when switching documents.
    func reset() {
        previousPatches = [:]
        previousText = ""
    }
}
