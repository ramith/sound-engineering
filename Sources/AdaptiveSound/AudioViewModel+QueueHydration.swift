import Foundation
import LibraryStore

// MARK: - AudioViewModel queue hydration + cursor persistence (S10.2, sub-step 2c)

//
// Read-side of the persistent queue: on launch (when the store signals ready) restore the queue
// from the built-in "current" playlist, RESTORE-PAUSED at the saved track + offset — never
// auto-play (founder brainstorm §0.2). The now-playing cursor (position/offset/shuffle/repeat)
// lives in UserDefaults, NOT a schema column, so S10.2 adds no migration (the queue rows survive
// in the DB as-is; DUR-1 still applies to a future schema change). A user edit BEFORE the store
// is ready SUPERSEDES hydration — their queue wins (the `hasUserEditedQueue` guard).

@MainActor
extension AudioViewModel {
    private enum QueueCursorKey {
        static let position = "queue.cursor.position"
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
                var items: [QueueItem] = []
                for entry in entries {
                    guard let track = try await store.track(id: entry.trackID) else { continue }
                    let file = AudioFile(
                        name: track.title ?? track.name, relativePath: "",
                        absoluteURL: track.url, format: track.format,
                        durationSeconds: 0, trackID: track.id
                    )
                    items.append(QueueItem(file: file))
                }
                // The user may have played something during the awaits — their queue wins.
                guard !hasUserEditedQueue, queue.isEmpty, !items.isEmpty else { return }
                queue = items // direct set — do NOT scheduleQueueMirror (never re-write what we read)
                restoreCursor(itemCount: items.count)
                logUX("queue hydrated: \(items.count) track(s) restored (paused)")
            } catch {
                logUX("queue hydrate failed: \(error)")
            }
        }
    }

    /// Restore selection + offset + shuffle/repeat, PAUSED: `isPlaying` stays false; the saved
    /// offset is stashed in `pausedResumePosition` so the FIRST Play resumes there (reusing the
    /// position-preserving resume path).
    private func restoreCursor(itemCount: Int) {
        let defaults = UserDefaults.standard
        if let position = defaults.object(forKey: QueueCursorKey.position) as? Int,
           position >= 0, position < itemCount {
            selectedTrackIndex = position
            let offset = defaults.double(forKey: QueueCursorKey.offset)
            if offset > 0 { pausedResumePosition = offset }
        }
        shuffleEnabled = defaults.bool(forKey: QueueCursorKey.shuffle)
        repeatMode = defaults.integer(forKey: QueueCursorKey.repeatMode)
    }

    /// Persist the now-playing cursor (position/offset/shuffle/repeat). Called on quit-flush
    /// (`+Lifecycle.shutdown`), so a clean quit restores exactly where you left off.
    func persistQueueCursor() {
        let defaults = UserDefaults.standard
        if let index = selectedTrackIndex {
            defaults.set(index, forKey: QueueCursorKey.position)
        } else {
            defaults.removeObject(forKey: QueueCursorKey.position)
        }
        defaults.set(playbackPosition, forKey: QueueCursorKey.offset)
        defaults.set(shuffleEnabled, forKey: QueueCursorKey.shuffle)
        defaults.set(repeatMode, forKey: QueueCursorKey.repeatMode)
    }
}
