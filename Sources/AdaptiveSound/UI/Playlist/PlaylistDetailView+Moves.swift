import LibraryBrowseKit
import SwiftUI

// MARK: - PlaylistDetailView + moves (S10.8 E4 — Move to Top / Up / Down / to Bottom)

/// The keyboard, menu and VoiceOver path to reorder a playlist, which only a drag could do before
/// (design §C's recorded exception). Each move plans over ALL the entries with `ListMove` — a
/// missing-file row keeps its place, as it does under a drag — and persists through the drag's own
/// `reorderEntries`. The keys live beside the track list's other keys, in the main file.
extension PlaylistDetailView {
    /// The row context menu's moves: all four, each showing its shortcut, disabled at the edges.
    /// (A context menu only SHOWS a shortcut; the list's key handler is what acts on it.)
    @ViewBuilder
    func moveMenuItems(for entryID: Int64, at position: Int) -> some View {
        let available = availableMoves(at: position)
        ForEach(ListMove.allCases, id: \.self) { move in
            Button(move.title) { perform(move, on: entryID) }
                .keyboardShortcut(move.arrow, modifiers: move.modifiers)
                .disabled(!available.contains(move))
        }
    }

    /// The same moves as VoiceOver custom actions — only the ones that would do something.
    func moveAccessibilityActions(for entryID: Int64, at position: Int) -> some View {
        ForEach(availableMoves(at: position), id: \.self) { move in
            Button(move.title) { perform(move, on: entryID) }
        }
    }

    /// The moves that would change something for the row at `position` (O(1) — read per visible
    /// row on every render).
    private func availableMoves(at position: Int) -> [ListMove] {
        ListMove.allCases.filter {
            $0.isAvailable(forRowsAt: CollectionOfOne(position), count: model.detail.count)
        }
    }

    /// Move one entry, keeping it selected and in view (the list scrolls once the rows re-sequence),
    /// and tell VoiceOver where it landed. Does nothing at the edge.
    func perform(_ move: ListMove, on entryID: Int64) {
        guard let order = move.reordering(model.detail.map(\.id), moving: [entryID]),
              let position = order.firstIndex(of: entryID) else { return }
        selectedEntryID = entryID
        revealEntryID = entryID
        model.reorderEntries(order)
        AccessibilityNotification.Announcement("Position \(position + 1) of \(order.count)").post()
    }
}
