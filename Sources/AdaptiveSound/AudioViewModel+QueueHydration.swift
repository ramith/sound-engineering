import Foundation
import LibraryStore

// MARK: - AudioViewModel queue hydration + cursor persistence (S10.2, sub-step 2c)

//
// Read-side of the persistent queue: on launch (when the store signals ready) restore the queue
// from the built-in "current" playlist, RESTORE-PAUSED at the saved track + offset — never
// auto-play (founder brainstorm §0.2). The now-playing cursor lives in UserDefaults, NOT a schema
// column, so S10.2 adds no migration (the queue rows survive in the DB as-is; DUR-1 still applies
// to a future schema change). A user edit BEFORE the store is ready SUPERSEDES hydration — their
// queue wins (the `hasUserEditedQueue` guard).
//
// Cursor durability (QA break-it #2/#3): the cursor is stored as (position, trackID-at-position)
// and RESOLVED tolerantly on restore — an exact (position, id) match, else the id found anywhere,
// else start-at-top. So a between-session queue shift (a track deleted while the app was closed
// holes the entries) or a stale cursor after a non-clean exit degrades to "start at top", NEVER a
// silent wrong-track/wrong-offset resume. Periodic (not quit-only) cursor persistence to shrink
// the crash-divergence window is deferred durability polish = DUR-1.

@MainActor
extension AudioViewModel {
    private enum QueueCursorKey {
        static let position = "queue.cursor.position"
        static let positionTrackID = "queue.cursor.positionTrackID"
        static let offset = "queue.cursor.offset"
        static let shuffle = "queue.cursor.shuffle"
        static let repeatMode = "queue.cursor.repeatMode"
    }

    /// Restore the queue from the persistent "current" playlist, ONCE, on launch — RESTORE-PAUSED.
    /// No-op if the user already edited the queue (superseded), if already hydrated, or if the
    /// store isn't ready. Wired by the composition root to `LibraryModel.onStoreReady`.
    func hydrateQueueOnLaunch() {
        guard !queueHydrated, !hasUserEditedQueue, queue.isEmpty, let store = library?.store else { return }
        queueHydrated = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let playlistID = try await store.currentPlaylistID()
                let entries = try await store.entries(inPlaylist: playlistID)
                // ONE batched read for the whole queue (QA #4 — no per-entry N+1), reusing the
                // display adapter so restored AudioFiles carry the SAME metadata + duration the
                // live queue was built with (QA #5a — no "--:--" relaunch regression).
                let byID = try await store.tracksDisplay(ids: entries.map(\.trackID))
                let items = entries.compactMap { entry in
                    byID[entry.trackID].map { QueueItem(file: AudioFile($0)) }
                }
                // The user may have acted during the awaits — their queue wins.
                guard !hasUserEditedQueue, queue.isEmpty, !items.isEmpty else { return }
                queue = items // direct set — do NOT scheduleQueueMirror (never re-write what we read)
                restoreCursor(itemCount: items.count)
                logUX("queue hydrated: \(items.count) track(s) restored (paused)")
            } catch {
                logUX("queue hydrate failed: \(error)")
            }
        }
    }

    /// Restore selection + offset + shuffle/repeat, PAUSED: `isPlaying` stays false. The offset is
    /// clamped to the resolved track's duration, stashed in `pausedResumePosition` so the FIRST
    /// Play resumes there (reusing the position-preserving resume seek), and mirrored into
    /// `playbackPosition` so the scrubber shows the resume point rather than 0:00 (QA #5b/#5c).
    private func restoreCursor(itemCount: Int) {
        let defaults = UserDefaults.standard
        if let index = resolveCursorPosition(itemCount: itemCount) {
            selectedTrackIndex = index // didSet clears the (nil) resume point first — order matters
            let saved = max(0, defaults.double(forKey: QueueCursorKey.offset))
            let duration = queue[index].file.durationSeconds
            let offset = duration > 0 ? min(saved, duration) : saved
            if offset > 0 {
                pausedResumePosition = offset
                playbackPosition = offset
            }
        }
        shuffleEnabled = defaults.bool(forKey: QueueCursorKey.shuffle)
        repeatMode = min(max(0, defaults.integer(forKey: QueueCursorKey.repeatMode)), 2) // QA #7 clamp
    }

    /// Resolve the saved cursor to a CURRENT queue index, tolerating a between-session shift (QA
    /// #2). Prefer an EXACT (position, trackID) match; else find the saved trackID anywhere
    /// (dup-safe: first match); else nil (start at top). A cursor from before `positionTrackID`
    /// existed has no saved id → best-effort by range only.
    private func resolveCursorPosition(itemCount: Int) -> Int? {
        let defaults = UserDefaults.standard
        guard let position = defaults.object(forKey: QueueCursorKey.position) as? Int else { return nil }
        let savedTrackID = (defaults.object(forKey: QueueCursorKey.positionTrackID) as? Int).map(Int64.init)
        if position >= 0, position < itemCount {
            if let savedTrackID {
                if queue[position].file.trackID == savedTrackID { return position }
            } else {
                return position
            }
        }
        if let savedTrackID {
            return queue.firstIndex { $0.file.trackID == savedTrackID }
        }
        return nil
    }

    /// Persist the now-playing cursor (position + trackID-at-position, offset, shuffle, repeat).
    /// Called on quit-flush (`+Lifecycle.shutdown`), so a clean quit restores exactly where you
    /// left off. (Periodic persistence for crash resilience = DUR-1; the tolerant resolve above
    /// keeps a stale cursor safe.)
    func persistQueueCursor() {
        let defaults = UserDefaults.standard
        if let index = selectedTrackIndex, index >= 0, index < queue.count {
            defaults.set(index, forKey: QueueCursorKey.position)
            if let trackID = queue[index].file.trackID {
                defaults.set(Int(trackID), forKey: QueueCursorKey.positionTrackID)
            } else {
                defaults.removeObject(forKey: QueueCursorKey.positionTrackID)
            }
        } else {
            defaults.removeObject(forKey: QueueCursorKey.position)
            defaults.removeObject(forKey: QueueCursorKey.positionTrackID)
        }
        defaults.set(playbackPosition, forKey: QueueCursorKey.offset)
        defaults.set(shuffleEnabled, forKey: QueueCursorKey.shuffle)
        defaults.set(repeatMode, forKey: QueueCursorKey.repeatMode)
    }
}
