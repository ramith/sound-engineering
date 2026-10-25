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
// play verb — is never thrown away, and neither is the stored queue: it JOINS the restored queue right after
// the restored song, where it goes when the restore comes first (`playTrackNextNow` puts an opened file
// right after the song selected), so the two orders end in the same queue. A song the user started plays on;
// otherwise the restored song is selected at its place. Either way the result is written.
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

    private func restoreQueue(from store: LibraryStore) async {
        var fromLegacy = false
        do {
            if let stored = try await storedRecord(in: store) {
                fromLegacy = stored.legacy
                let resolved = try await resolve(stored.record, in: store)
                // Read after the awaits: what the user queued meanwhile joins too.
                if !resolved.items.isEmpty {
                    let joining = queue.count
                    install(resolved)
                    let place = resolved.cursor.map { "song \($0 + 1) at \(secs(resolved.offset))s" } ?? "none selected"
                    logUX("queue restored (paused): \(resolved.items.count) song(s), \(place)"
                        + (joining > 0 ? ", \(joining) queued before it joining after that song" : "")
                        + (shufflePass != nil ? ", in a shuffle pass" : ""))
                }
            }
        } catch {
            // Left as stored: the first change of this session writes the queue then.
            logUX("queue restore failed: \(error)")
            queueStateBook.restored = true
            return
        }
        // The stored state becomes the queue as it now is: restored (a gone song dropped), joined, or the
        // user's own when nothing was stored.
        queueStateBook.restored = true
        guard !queue.isEmpty else { return }
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

    /// Put the restored queue in place, with what was queued before it (`joining`) right after the restored
    /// song — or at the end when none was selected — in the pass too: next, in order, counted as played
    /// (`ShufflePass.insertNext`, Play Next's rule). A song the user started before the restore plays on, in
    /// its new row, and what plays after it follows the joined queue (`keepOnDeck`).
    ///
    /// Otherwise the restored song is selected PAUSED: `isPlaying` stays false. The pass first, so the
    /// selection finds it on its own song. The offset is clamped to the song's length, stashed in
    /// `resumePoint` (that slot's) so the FIRST Play resumes there, and mirrored into `playbackPosition` so the
    /// scrubber shows it rather than 0:00 (QA #5b/#5c).
    private func install(_ resolved: QueueResumeRecord.Resolved<AudioFile>) {
        let joining = queue
        let started = selectedSlotID
        let armed = onDeckSlotID
        let restored = resolved.items.map { QueueItem(file: $0) }
        let joinAt = resolved.cursor.map { $0 + 1 } ?? restored.count
        queue = Array(restored[..<joinAt]) + joining + Array(restored[joinAt...])
        if shuffleEnabled {
            var pass = resolved.shuffle?.relabeled { restored.indices.contains($0) ? restored[$0].id : nil }
            pass?.insertNext(joining.map(\.id))
            shufflePass = pass
        }
        if let started {
            selectedTrackIndex = queueRow(of: started)
            keepOnDeck(armed: armed)
            return
        }
        guard let index = resolved.cursor else { return }
        selectedTrackIndex = index // didSet clears the (nil) resume point first — order matters
        let duration = restored[index].file.durationSeconds
        let offset = duration > 0 ? min(resolved.offset, duration) : resolved.offset
        if offset > 0 {
            resumePoint = ResumePoint(slot: restored[index].id, seconds: offset)
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
