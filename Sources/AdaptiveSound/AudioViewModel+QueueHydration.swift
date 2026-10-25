import Foundation
import LibraryStore
import PlaybackQueueKit

// MARK: - AudioViewModel: the queue comes back at launch (S10.2 2c; R1.1-B, council C-65)

//
// The read side of the queue's resume record (`+QueueMirror`): on launch, when the store signals ready, the
// queue comes back RESTORE-PAUSED — the same songs, loose files included, the selected one at its place, and
// with shuffle on the same pass (its order, place and history) — never auto-play (founder brainstorm §0.2). A
// user edit BEFORE the store is ready SUPERSEDES the restore: their queue wins (the `hasUserEditedQueue`
// guard), and is written over the stored one.
//
// What can't be found any more is dropped the tolerant way (`QueueResumeRecord.resolved`, QA break-it #2/#3):
// a song deleted while the app was closed leaves the queue, and when it was the selected one the queue starts
// at the top — or, under shuffle, at the pass's next song — never another song at the old offset. A loose file
// comes back by its path, found or not; the dead-file badge says the rest.
//
// A library a build before the record left (R1.1-A and earlier) holds no record: its queue is the "current"
// playlist's songs, its cursor three keys in the defaults (written only at a clean quit). They are read once,
// the tolerant way they always were, written as the record, and the keys removed.
//
// Shuffle and repeat are listening settings, not the record (R1.1-A): they come back at every launch from the
// listener's settings (`+ListeningSettings`). A kept pass is used only when shuffle is on.

@MainActor
extension AudioViewModel {
    /// The cursor a build before the record kept in the defaults.
    private enum LegacyCursorKey {
        static let position = "queue.cursor.position"
        static let positionTrackID = "queue.cursor.positionTrackID"
        static let offset = "queue.cursor.offset"
    }

    /// Restore the queue from the store, ONCE, on launch — RESTORE-PAUSED — then open its writer. The queue
    /// the user already built (superseded), or a store that isn't ready, restores nothing. Wired by the
    /// composition root to `LibraryModel.onStoreReady`.
    func hydrateQueueOnLaunch() {
        guard !queueHydrated, let store = library?.store else { return }
        queueHydrated = true
        work.spawn { @MainActor [weak self] in
            await self?.restoreQueue(from: store)
        }
    }

    private func restoreQueue(from store: LibraryStore) async {
        var restored = false
        var fromLegacy = false
        do {
            if !hasUserEditedQueue, queue.isEmpty, let stored = try await storedRecord(in: store) {
                fromLegacy = stored.legacy
                let resolved = try await resolve(stored.record, in: store)
                // The user may have acted during the awaits — their queue wins.
                if !hasUserEditedQueue, queue.isEmpty, !resolved.items.isEmpty {
                    install(resolved)
                    restored = true
                    let place = resolved.cursor.map { "song \($0 + 1) at \(secs(resolved.offset))s" } ?? "none selected"
                    logUX("queue restored (paused): \(resolved.items.count) song(s), \(place)"
                        + (shufflePass != nil ? ", in a shuffle pass" : ""))
                }
            }
        } catch {
            // Left as stored: the first change of this session writes the queue then.
            logUX("queue restore failed: \(error)")
            queueStateBook.restored = true
            return
        }
        // The stored state is now the queue as restored (a gone song dropped), or the user's own queue.
        let superseded = !restored && hasUserEditedQueue
        queueStateBook.restored = true
        guard restored || superseded else { return }
        queueStateChanged()
        if fromLegacy {
            await queueStateWriter.flush()
            if queueStateBook.written != nil {
                forgetLegacyCursor()
            }
        }
    }

    /// The stored record — or, in a library a build before it left, the record its "current" playlist and the
    /// defaults' cursor make. Nil when neither holds a queue.
    private func storedRecord(in store: LibraryStore) async throws -> (record: QueueResumeRecord, legacy: Bool)? {
        if let stored = try await store.queueState() {
            return try await (Self.decoded(stored), false)
        }
        let entries = try await store.entries(inPlaylist: store.currentPlaylistID())
        guard !entries.isEmpty else { return nil }
        let record = QueueResumeRecord.legacy(
            trackIDs: entries.map(\.trackID),
            cursorRow: defaults.object(forKey: LegacyCursorKey.position) as? Int,
            cursorTrackID: (defaults.object(forKey: LegacyCursorKey.positionTrackID) as? Int).map(Int64.init),
            offset: defaults.double(forKey: LegacyCursorKey.offset)
        )
        return (record, true)
    }

    /// A stored record decoded off the main actor (a whole-library queue is half a megabyte of JSON).
    @concurrent
    private nonisolated static func decoded(_ stored: StoredQueueState) async throws -> QueueResumeRecord {
        try QueueResumeRecord(storedQueue: stored.record, offset: stored.offset ?? 0)
    }

    /// Each slot found again: library songs in ONE batched read (QA #4 — no per-song N+1), through the
    /// display adapter, so they carry the same metadata and length the live queue was built with (QA #5a —
    /// no "--:--"); loose files by their paths.
    private func resolve(_ record: QueueResumeRecord, in store: LibraryStore) async throws
        -> QueueResumeRecord.Resolved<AudioFile> {
        let ids = record.slots.compactMap { slot -> Int64? in
            if case let .track(id) = slot {
                id
            } else {
                nil
            }
        }
        let byID = try await store.tracksDisplay(ids: ids)
        return record.resolved { slot in
            switch slot {
            case let .track(id): byID[id].map { AudioFile($0) }
            case let .loose(path): AudioFile(restoringLoose: path)
            }
        }
    }

    /// Put the restored queue in place, PAUSED: `isPlaying` stays false. The pass first, so the selection
    /// finds it on its own song. The offset is clamped to the song's length, stashed in `resumePoint` (that
    /// slot's) so the FIRST Play resumes there, and mirrored into `playbackPosition` so the scrubber shows it
    /// rather than 0:00 (QA #5b/#5c).
    private func install(_ resolved: QueueResumeRecord.Resolved<AudioFile>) {
        let items = resolved.items.map { QueueItem(file: $0) }
        queue = items
        if shuffleEnabled {
            shufflePass = resolved.shuffle?.relabeled { items.indices.contains($0) ? items[$0].id : nil }
        }
        guard let index = resolved.cursor else { return }
        selectedTrackIndex = index // didSet clears the (nil) resume point first — order matters
        let duration = items[index].file.durationSeconds
        let offset = duration > 0 ? min(resolved.offset, duration) : resolved.offset
        if offset > 0 {
            resumePoint = ResumePoint(slot: items[index].id, seconds: offset)
            playbackPosition = offset
        }
    }

    /// The legacy cursor keys, once their queue is written as the record.
    private func forgetLegacyCursor() {
        for key in [LegacyCursorKey.position, LegacyCursorKey.positionTrackID, LegacyCursorKey.offset] {
            defaults.removeObject(forKey: key)
        }
    }
}
