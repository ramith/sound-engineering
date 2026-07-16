import SwiftUI

// MARK: - PlaylistDetailView + actions (split out for type-body length)

/// Play / reorder / keyboard-nav / restore-toast actions for the playlist detail, plus the
/// missing-file (F) helpers. A same-type extension, split from `PlaylistDetailView` for type-body
/// length; reaches its `internal` state.
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

    /// The "N file(s) missing" help string (real pluralization) for the header affordance.
    var missingHelp: String {
        let count = model.missingEntryCount
        return "\(count) \(count == 1 ? "file" : "files") missing"
    }

    /// Play the playlist (replace queue, undoable), optionally from a tapped row, and raise the
    /// transient restore-queue affordance — ONLY if a replace actually happened (an all-unavailable
    /// playlist no-ops, and must not resurface a stale toast from an earlier real Play).
    func playNow(startingAt entryID: Int64? = nil) {
        if model.playPlaylist(startingAt: entryID) { raiseRestoreToast() }
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
        Task { await model.reorderEntries(ids) }
        return true
    }

    /// ↑/↓ traverse only the AVAILABLE (playable) rows — the "unavailable" (missing-file) rows are
    /// non-interactive except via their context menu (Locate / Remove), so selection skips them (F).
    func moveSelection(by delta: Int) -> KeyPress.Result {
        let ids = model.detail.filter(\.isAvailable).map(\.id)
        guard !ids.isEmpty else { return .ignored }
        guard let current = selectedEntryID, let index = ids.firstIndex(of: current) else {
            selectedEntryID = ids.first
            return .handled
        }
        let next = index + delta
        guard next >= 0, next < ids.count else { return .ignored }
        selectedEntryID = ids[next]
        return .handled
    }

    func playSelected() -> KeyPress.Result {
        guard let id = selectedEntryID else { return .ignored }
        playNow(startingAt: id)
        return .handled
    }

    func removeSelected() -> KeyPress.Result {
        guard let id = selectedEntryID else { return .ignored }
        // Pre-select the neighbor (next, else previous) so selection lands there — not back at the
        // top — once the async remove + reload lands. Use the SAME available-row set `moveSelection`
        // traverses, so the neighbor is a selectable row (not an unavailable placeholder).
        let ids = model.detail.filter(\.isAvailable).map(\.id)
        if let index = ids.firstIndex(of: id) {
            selectedEntryID = index + 1 < ids.count ? ids[index + 1]
                : (index - 1 >= 0 ? ids[index - 1] : nil)
        }
        Task { await model.removeEntry(id) }
        return .handled
    }
}
