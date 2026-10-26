import Foundation
import LibraryStore
import PlaybackQueueKit

// MARK: - AudioViewModel: the queue comes back at launch (S10.2 2c; R1.1-B, council C-65)

//
// The read side of the queue's resume record (`+QueueMirror`): on launch, when the store signals ready, the
// queue comes back RESTORE-PAUSED — the same songs, loose files included, the selected one at its place, and
// with shuffle on the same pass (its order, place and history) — never auto-play (founder brainstorm §0.2).
//
// What the user queued BEFORE the restore — a file opened at launch (Open With, a drop on the Dock icon), any
// play verb — is never thrown away, and neither is the stored queue: it JOINS the restored queue where doing
// the same after the restore would have put it (`QueueJoin`, PlaybackQueueKit: an opened file right after the
// restored song — first when none is selected — moving the restored queue's slot of the same file, never
// doubling it), so the two orders end in the same queue, song, next song and record. A song the user started
// plays on; otherwise the restored song is selected at its place. Either way the result is written.
//
// What can't be found any more is dropped the tolerant way (`QueueResumeRecord.resolved`, QA break-it #2/#3):
// a song deleted while the app was closed leaves the queue, and when it was the selected one the queue starts
// at the top — or, under shuffle, at the pass's next song — never another song at the old offset. A loose file
// comes back by its path, found or not; the dead-file badge says the rest. A damaged record restores nothing,
// and the session's first change writes the queue whole. A store that fails the read is read once more; if it
// fails again the writer stays closed for the session, so the stored queue is never overwritten by one this
// launch never saw (review N1).
//
// A library a build before the record left (R1.1-A and earlier) holds no record: its queue is the "current"
// playlist's songs, its cursor three keys in the defaults (written only at a clean quit). They are read once,
// the tolerant way they always were, and written as the record; then the playlist's entries and the keys are
// cleared — dead data from then on (review N10). The built-in playlist itself stays.
//
// Shuffle and repeat are listening settings, not the record (R1.1-A): they come back at every launch from the
// listener's settings (`+ListeningSettings`). A kept pass is used only when shuffle is on.
//
// From the restore on, the live queue follows the library: each time its content changes
// (`LibraryModel.libraryRevision` — a metadata pass, or "Use this drive" re-rooting a folder's songs to new
// paths), the queue's library songs are read again by id, and a song whose file moved plays from its new path
// — the armed next song re-armed there — without a relaunch. A slot whose song left the library keeps its old
// file, as before; the record drops it at the next restore.

@MainActor
extension AudioViewModel {
    /// The cursor a build before the record kept in the defaults.
    private enum LegacyCursorKey {
        static let position = "queue.cursor.position"
        static let positionTrackID = "queue.cursor.positionTrackID"
        static let offset = "queue.cursor.offset"
    }

    /// Restore the queue from the store, ONCE, on launch — RESTORE-PAUSED, joined by anything queued before —
    /// then open its writer, and follow the library's changes from then on. A store that isn't ready restores
    /// nothing. Wired by the composition root to `LibraryModel.onStoreReady`.
    func hydrateQueueOnLaunch() {
        guard !queueHydrated, let store = library?.store else { return }
        queueHydrated = true
        work.spawn { @MainActor [weak self] in
            await self?.restoreQueue(from: store)
            self?.followLibraryRevisions()
        }
    }

    /// What the launch's read of the store found.
    private enum StoredQueueRead {
        /// A queue: the record's slots found again — from a build before the record when `legacy`.
        case found(QueueResumeRecord.Resolved<QueueItem>, legacy: Bool)
        /// Nothing to restore: no queue was stored, or the record is damaged.
        case nothing
        /// The store failed the read twice: what is stored is unknown.
        case unreadable
    }

    private func restoreQueue(from store: LibraryStore) async {
        var fromLegacy = false
        switch await readStoredQueue(from: store) {
        case .unreadable:
            return // the writer stays closed: this session's queue must not overwrite one it never read
        case .nothing:
            break
        case let .found(resolved, legacy):
            fromLegacy = legacy
            if !resolved.items.isEmpty {
                let joining = queue.count
                install(resolved)
                let place = resolved.cursor.map { "song \($0 + 1) at \(secs(resolved.offset))s" } ?? "none selected"
                logUX("queue restored (paused): \(resolved.items.count) song(s), \(place)"
                    + (joining > 0 ? ", joined by \(joining) queued before it" : "")
                    + (shufflePass != nil ? ", in a shuffle pass" : ""))
            }
        }
        // The stored state becomes the queue as it now is: restored (a gone song dropped), joined, or the
        // user's own when nothing was stored.
        queueStateBook.restored = true
        guard !queue.isEmpty else { return }
        queueStateChanged()
        if fromLegacy {
            await finishLegacyCarryOver(in: store)
        }
    }

    /// The stored queue, its slots found again. A damaged record is nothing to restore (left as stored: the
    /// session's first change writes the queue whole); any other failure — the store, the disk — is tried once
    /// more, and a second one leaves what is stored unknown.
    private func readStoredQueue(from store: LibraryStore) async -> StoredQueueRead {
        for attempt in 1 ... 2 {
            do {
                guard let stored = try await storedRecord(in: store) else { return .nothing }
                return try await .found(resolve(stored.record, in: store), legacy: stored.legacy)
            } catch let damaged as DecodingError {
                logUX("queue restore: the stored queue is damaged — nothing restored: \(damaged)")
                return .nothing
            } catch {
                logUX(attempt == 1 ? "queue restore failed, reading once more: \(error)"
                    : "queue restore failed again — this session's queue is not kept: \(error)")
            }
        }
        return .unreadable
    }

    /// The carry-over's end: once the old queue is written as the record, the "current" playlist's entries
    /// and the cursor's keys are dead data — cleared, the entries through the store's playlist API. The
    /// built-in playlist itself stays. Nothing is cleared when the write failed: the next launch reads them
    /// again.
    private func finishLegacyCarryOver(in store: LibraryStore) async {
        await queueStateWriter.flush()
        guard queueStateBook.written != nil else { return }
        do {
            try await store.clearEntries(playlistID: store.currentPlaylistID())
        } catch {
            logUX("queue: the old \"current\" playlist's entries were not cleared: \(error)")
        }
        forgetLegacyCursor()
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
        -> QueueResumeRecord.Resolved<QueueItem> {
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
            case let .track(id): byID[id].map { QueueItem(file: AudioFile($0)) }
            case let .loose(path): QueueItem(file: AudioFile(looseFileAt: URL(fileURLWithPath: path)))
            }
        }
    }

    /// Put the restored queue in place, joined by what was queued before it (`QueueJoin`: where doing the same
    /// after the restore would put it), with the shuffle pass the join leaves. A song the user started before
    /// the restore plays on, in its new row, and what plays after it follows the joined queue (`keepOnDeck`).
    ///
    /// Otherwise the restored song is selected PAUSED: `isPlaying` stays false. The pass first, so the
    /// selection finds it on its own song. The offset is clamped to the song's length, stashed in
    /// `resumePoint` (that slot's) so the FIRST Play resumes there, and mirrored into `playbackPosition` so the
    /// scrubber shows it rather than 0:00 (QA #5b/#5c).
    private func install(_ resolved: QueueResumeRecord.Resolved<QueueItem>) {
        let started = selectedSlotID != nil ? selectedTrackIndex : nil
        let armed = onDeckSlotID
        let joined = resolved.joined(by: queue, started: started, shuffled: shuffleEnabled) {
            $0.file.id == $1.file.id
        }
        // The pass over what came before goes first, so it never follows every restored slot (review S3).
        shufflePass = nil
        queue = joined.items
        shufflePass = joined.pass
        if started != nil {
            selectedTrackIndex = joined.selected
            keepOnDeck(armed: armed)
            return
        }
        guard let index = joined.selected else { return }
        selectedTrackIndex = index // didSet clears the (nil) resume point first — order matters
        let duration = queue[index].file.durationSeconds
        let offset = duration > 0 ? min(resolved.offset, duration) : resolved.offset
        if offset > 0 {
            resumePoint = ResumePoint(slot: queue[index].id, seconds: offset)
            playbackPosition = offset
        }
    }

    /// The legacy cursor keys, once their queue is written as the record.
    private func forgetLegacyCursor() {
        for key in [LegacyCursorKey.position, LegacyCursorKey.positionTrackID, LegacyCursorKey.offset] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Following the library

    /// Re-read the queue's library songs each time the library's content changes (see the file's header).
    /// Observation fires once per registration, so each change registers the next.
    func followLibraryRevisions() {
        guard let library else { return }
        withObservationTracking {
            _ = library.libraryRevision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.relinkLibrarySongs()
                self?.followLibraryRevisions()
            }
        }
    }

    /// Read the queue's library songs from the store by id, and give each whose file moved its new path.
    func relinkLibrarySongs() {
        guard let store = library?.store else { return }
        let ids = Array(Set(queue.compactMap(\.file.trackID)))
        guard !ids.isEmpty else { return }
        work.spawn { @MainActor [weak self] in
            guard let songs = try? await store.tracksDisplay(ids: ids) else { return }
            self?.relink(songs)
        }
    }

    /// The queue with each library song whose stored file differs from its slot's read again (same slot).
    /// When the armed next song moved, it is armed again at its new path.
    private func relink(_ songs: [Int64: LibraryTrackDisplay]) {
        let armed = onDeckSlotID
        var moved: Set<UUID> = []
        let relinked = queue.map { item -> QueueItem in
            guard let id = item.file.trackID, let song = songs[id], song.url != item.file.absoluteURL else {
                return item
            }
            moved.insert(item.id)
            return QueueItem(file: AudioFile(song), id: item.id)
        }
        guard !moved.isEmpty else { return }
        logUX("queue: \(moved.count) song(s) moved in the library — playing from their new paths")
        queue = relinked
        if let armed, moved.contains(armed), onDeckIsLive {
            armOnDeck(index: queueRow(of: armed))
        }
    }
}
