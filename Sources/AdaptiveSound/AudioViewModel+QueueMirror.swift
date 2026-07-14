import Foundation

// MARK: - AudioViewModel queue → "current"-playlist mirror (S10.2, design §2/§7)

//
// The in-memory `queue` is authoritative for playback; the built-in "current" playlist is a
// DURABLE MIRROR of it. Every queue EDIT schedules a debounced full-SNAPSHOT resync (clear +
// append the current track-ids, one txn via `LibraryStore.replaceEntries`). Rationale (per the
// architect/the-fool gate): a full snapshot needs no stable entry-ids, no serial patch-back
// chain, and no reorder-before-append-acks ordering hazard — the recovery path IS the normal
// path, so a dropped write self-heals on the next edit. ADVANCE never mirrors (the rows don't
// change when the cursor moves), so nothing touches the store on the gapless seam.
//
// Slots with no `trackID` (a loose file with no library row) are skipped in the snapshot; there
// is no loose-file queue entry point in the UI yet, so in practice every slot is a library play.

@MainActor
extension AudioViewModel {
    /// Debounce interval for the snapshot mirror — long enough to coalesce an edit burst
    /// (drag-reorder, multi-add), short enough to persist promptly.
    private static let queueMirrorDebounce: Duration = .milliseconds(250)

    /// Schedule a debounced snapshot of `queue` into the built-in "current" playlist. Cancels any
    /// pending mirror so only the settled queue is written. Call from every queue-EDITING verb.
    func scheduleQueueMirror() {
        hasUserEditedQueue = true // a real edit — supersedes any not-yet-run launch hydration
        queueMirrorTask?.cancel()
        queueMirrorTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.queueMirrorDebounce)
            guard !Task.isCancelled, let self else { return }
            await mirrorQueueNow()
        }
    }

    /// Snapshot the current queue's track-ids into the "current" playlist, now (used by the
    /// debounce + by the quit-flush in `+Lifecycle`). Errors are logged and left to self-heal on
    /// the next edit — never thrown into the UI. A no-op until the library store is ready.
    func mirrorQueueNow() async {
        guard let store = library?.store else { return }
        let trackIDs = queue.compactMap(\.file.trackID)
        // A queue slot with no library id (a loose file) cannot be persisted by the id-only
        // snapshot and WON'T survive a relaunch. There is no loose-file queue entry point in the
        // UI today, so this is latent — but never drop it silently (QA break-it #6). If a loose
        // entry point lands, route it through addLooseFileToPlaylist (which mints a trackID) first.
        if trackIDs.count != queue.count {
            logUX("queue mirror: \(queue.count - trackIDs.count) loose slot(s) without a library id "
                + "will NOT persist across relaunch")
        }
        do {
            let playlistID = try await store.currentPlaylistID()
            try await store.replaceEntries(playlistID: playlistID, trackIDs: trackIDs)
        } catch {
            logUX("queue mirror failed (will re-snapshot on next edit): \(error)")
        }
    }
}
