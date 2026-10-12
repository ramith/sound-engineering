import SwiftUI

// MARK: - PlaylistDetailView + actions (split out for type-body length)

/// Play / reorder / restore-toast actions for the playlist detail, plus the missing-file (F)
/// helpers. A same-type extension, split from `PlaylistDetailView` for type-body length; reaches
/// its `internal` state. (The keyboard-cursor keys live beside the track list, in the main file.)
extension PlaylistDetailView {
    /// Locate / Remove for a missing entry — shared by the badge menu, the row context menu, and the
    /// VoiceOver rotor so all three stay in sync.
    @ViewBuilder
    func missingRowActions(_ row: PlaylistDetailEntry) -> some View {
        Button("Locate…") { locatingEntryID = row.id }
        Button("Remove from Playlist", role: .destructive) {
            Task { await model.removeEntry(row.id) }
        }
    }

    /// Play the playlist (replace queue, undoable), optionally from a tapped row, and offer the undo
    /// — the Library card's one restore toast (`QueueRestoreToast`, review 18) — ONLY if a replace
    /// actually happened (an all-unavailable playlist no-ops, and must not resurface a stale toast
    /// from an earlier real Play).
    func playNow(startingAt entryID: Int64? = nil) {
        if model.playPlaylist(startingAt: entryID) {
            library.offerQueueRestore()
        }
    }

    /// The header's Shuffle (E4): Play's replace, from a random song with shuffle on — and Play's undo.
    func shuffleNow() {
        if model.shufflePlaylist() {
            library.offerQueueRestore()
        }
    }

    /// A row's Play Next: that song after the current one, confirmed by the queue toast as on the
    /// album, artist and genre pages.
    func playEntryNext(_ entryID: Int64) {
        let added = model.playEntryNext(entryID)
        guard added > 0 else { return } // the entry is gone or unplayable: nothing went in, no toast
        library.showQueueToast(.playNext, added: added)
    }

    /// Move `fromID` to land AT `toEntryID`'s row and persist the new order — matching the queue's
    /// convention (`AudioViewModel.moveByDrop`): dragging DOWN inserts AFTER the target, UP before
    /// it, so the last slot is reachable and the two lists behave identically.
    func moveEntry(fromID: Int64, toEntryID: Int64) -> Bool {
        var ids = model.detail.map(\.id)
        guard let from = ids.firstIndex(of: fromID), let to = ids.firstIndex(of: toEntryID),
              from != to else { return false }
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: from < to ? to + 1 : to)
        model.reorderEntries(ids)
        return true
    }
}
