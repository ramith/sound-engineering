import SwiftUI

// MARK: - PlaylistDetailView + actions (split out for type-body length)

/// Play / reorder / restore-toast actions for the playlist detail, plus the missing-file (F) helpers
/// and the page's dialogs (E4). A same-type extension, split from `PlaylistDetailView` for type-body
/// length; reaches its `internal` state. (The keyboard-cursor keys live beside the track list, in the
/// main file.)
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

    /// Play the playlist (replace queue, undoable), optionally from a tapped row, and raise the
    /// transient restore-queue affordance — ONLY if a replace actually happened (an all-unavailable
    /// playlist no-ops, and must not resurface a stale toast from an earlier real Play).
    func playNow(startingAt entryID: Int64? = nil) {
        if model.playPlaylist(startingAt: entryID) {
            raiseRestoreToast()
        }
    }

    /// The header's Shuffle (E4): Play's replace, from a random song with shuffle on — and Play's undo.
    func shuffleNow() {
        if model.shufflePlaylist() {
            raiseRestoreToast()
        }
    }

    func raiseRestoreToast() {
        let token = (restoreToastToken ?? 0) &+ 1
        restoreToastToken = token
        restoreDismissTask?.cancel()
        restoreDismissTask = Task { [token] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, restoreToastToken == token else { return }
            restoreToastToken = nil
        }
    }

    func dismissRestoreToast() {
        restoreDismissTask?.cancel()
        restoreToastToken = nil
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

    // MARK: Dialogs (E4 — the app's themed dialog, one sheet)

    /// The sheet is up while a failure waits to be read or the bulk remove-missing waits on its
    /// confirmation. A dismissal clears the confirmation; a failure clears only through its OK — so a
    /// dismissal that lands just after a failure arrived (the confirmation's Remove, then the store
    /// failing) can't swallow it.
    var isShowingDialog: Binding<Bool> {
        Binding(get: { model.actionError != nil || confirmingRemoveMissing }, set: { shown in
            if !shown, model.actionError == nil {
                confirmingRemoveMissing = false
            }
        })
    }

    /// The ⋯ menu's Remove Missing…: confirm first (no undo — F review).
    func askToRemoveMissing() {
        confirmingRemoveMissing = true
    }

    /// The confirmation's Remove: close it, then drop every entry whose file is missing.
    func removeMissing() {
        confirmingRemoveMissing = false
        Task { await model.removeMissingEntries() }
    }

    func cancelRemoveMissing() {
        confirmingRemoveMissing = false
    }
}
