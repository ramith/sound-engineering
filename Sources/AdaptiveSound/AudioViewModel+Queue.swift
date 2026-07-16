import Foundation
import PlaybackQueueKit

// MARK: - AudioViewModel queue ops (Play Now / Play Next / Add to Queue / jump-play)

//
// The browse UI's play verbs, layered on the existing index-addressed engine
// (queue: [QueueItem] + selectedTrackIndex + the gapless on-deck pendingNextIndex).
// Callers convert LibraryTrackDisplay → AudioFile (see AudioFile+LibraryTrackDisplay).
// `playTrackNextNow` is the Songs-list single-track "insert after current + jump to play NOW".
//
// The pure DECISIONS live in PlaybackQueueKit, shared by the tests: whether an append re-arms
// the on-deck is `QueueAdvance.appendArmIndex`; the single-track jump-play index-remap
// (remove/insert slots + the current-index shift) is `QueueInsert.playNextNow`. The rest here
// is mechanical array + engine sequencing.
//
// S10.2: a queue slot is a `QueueItem` with a stable UUID identity (NOT its URL), so the SAME
// track may appear more than once — the S9 dedupe-on-add contract is retired. Reorder identity
// is `QueueItem.id` (see `movePlaylistItems`).

/// A one-level restore point for the "Play (replace queue)" undo (S10.3): the queue slots + the
/// selected index, snapshotted before a destructive replace.
struct QueueRestorePoint {
    let items: [QueueItem]
    let index: Int?
}

@MainActor
extension AudioViewModel {
    /// Replace the queue with `tracks` and start playing from `startAt`, first SNAPSHOTTING the
    /// current queue so the caller can offer a one-level "Restore previous queue" undo (S10.3
    /// D-play). Use this for the playlist "Play" verb; plain `playNow` stays the un-undoable path.
    func playNowWithUndo(_ tracks: [AudioFile], startAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        queueRestorePoint = QueueRestorePoint(items: queue, index: selectedTrackIndex)
        playNow(tracks, startAt: index)
    }

    /// Whether a "Restore previous queue" undo is available.
    var canRestorePreviousQueue: Bool {
        queueRestorePoint != nil
    }

    /// Restore the queue captured by the last `playNowWithUndo` (one-level). An empty previous queue
    /// clears; otherwise the slots are restored and playback resumes at the previously selected track
    /// (a pragmatic one-level undo — position within the track is not preserved). A previous queue
    /// with NO selection is restored with the engine stopped (never left playing a gone track).
    func restorePreviousQueue() {
        guard let point = queueRestorePoint else { return }
        queueRestorePoint = nil
        guard !point.items.isEmpty else {
            clearPlaylist()
            return
        }
        queue = point.items
        scheduleQueueMirror()
        if let index = point.index, index < queue.count {
            playTrack(at: index) // resume at the previously-selected track
        } else {
            selectedTrackIndex = nil
            stopPlayback() // no prior selection — restore the slots, stop the engine (no gone-track playback)
        }
    }

    /// Replace the queue with `tracks` and start playing from `startAt` (clamped).
    /// The destructive "play this album/these results now" action. `startPlayback`
    /// (via `playTrack`) re-primes the gapless on-deck.
    func playNow(_ tracks: [AudioFile], startAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        let start = min(max(0, index), tracks.count - 1)
        logUX("playNow: \(tracks.count) track(s), startAt=\(start)")
        queue = tracks.map { QueueItem(file: $0) }
        scheduleQueueMirror()
        playTrack(at: start)
    }

    /// Insert `tracks` immediately after the current track and arm the first of them as
    /// the on-deck — a single-slot override honored EVEN under shuffle (Music.app's
    /// "Play Next"), because it sets `pendingNextIndex` directly rather than routing
    /// through `computeNextIndex` (design §6; the multi-item forced-next FIFO is later).
    /// With nothing playing there is no "current" to insert after, so it appends.
    /// Returns the number of tracks added so the caller can raise a truthful "Added N…" toast.
    @discardableResult
    func playNext(_ tracks: [AudioFile]) -> Int {
        guard !tracks.isEmpty else { return 0 }
        guard let current = selectedTrackIndex else {
            return appendToQueue(tracks) // nothing selected → no "current" to insert after
        }
        let insertAt = min(current + 1, queue.count)
        logUX("playNext: \(tracks.count) track(s) after index \(current) (playing=\(isPlaying))")
        queue.insert(contentsOf: tracks.map { QueueItem(file: $0) }, at: insertAt)
        scheduleQueueMirror()
        // Playing → arm the inserted slot as the on-deck (single-slot override, honors
        // shuffle). Paused → the insert alone plays it next under LINEAR order (resume's
        // primeGaplessPipeline derives computeNextIndex(current) = current+1).
        if isPlaying { armOnDeck(index: insertAt) }
        return tracks.count
    }

    /// Insert `track` immediately after the current track and JUMP to play it NOW — the Songs-list
    /// double-click / Return / single-row "Play". Unlike `playNext` (which only ARMS the on-deck),
    /// this routes through `playTrack(at:)`, so the engine restarts on the inserted slot and
    /// `primeGaplessPipeline` re-primes the on-deck; the rest of the EXISTING queue follows after.
    ///
    /// If `track`'s URL already occurs in the queue, its FIRST occurrence is MOVED (removed then
    /// re-inserted) rather than a copy added — the pure index-remap (remove/insert slots + the
    /// current-index shift) is `QueueInsert.playNextNow`, shared by the tests.
    ///
    /// Edge cases:
    /// - Nothing playing (`selectedTrackIndex == nil`): front-insert (index 0) so the existing
    ///   queue follows; an empty queue simply becomes `[track]`.
    /// - Re-clicking the currently-playing track: RESTART it in place.
    ///
    /// No play-count increment is routed here: a jump-play is not a natural completion.
    func playTrackNextNow(_ track: AudioFile) {
        let move = QueueInsert.playNextNow(
            current: selectedTrackIndex,
            existing: queue.firstIndex { $0.file.id == track.id },
            count: queue.count
        )
        switch move {
        case let .restartCurrent(index):
            logUX("playTrackNextNow: restart current index \(index) '\(track.name)'")
            playTrack(at: index)
        case let .insertAndPlay(removeAt, insertAt):
            if let removeAt { queue.remove(at: removeAt) }
            queue.insert(QueueItem(file: track), at: insertAt)
            scheduleQueueMirror()
            logUX("playTrackNextNow: '\(track.name)' → index \(insertAt)"
                + (removeAt.map { " (moved from \($0))" } ?? "") + " (playing=\(isPlaying))")
            // playTrack overwrites selectedTrackIndex and re-primes the on-deck, so the stale
            // pre-mutation selection/pending never surfaces.
            playTrack(at: insertAt)
        }
    }

    /// Append `tracks` to the end of the queue. Re-arms the on-deck ONLY in the linear
    /// end-of-queue case (playing the last track with nothing on-deck, repeat-off) — see
    /// `QueueAdvance.appendArmIndex`; otherwise the existing primed pick is left untouched
    /// (append must never re-roll under shuffle or disturb a mid-list on-deck).
    /// Returns the number of tracks appended.
    @discardableResult
    func appendToQueue(_ tracks: [AudioFile]) -> Int {
        guard !tracks.isEmpty else { return 0 }
        let oldCount = queue.count
        logUX("appendToQueue: \(tracks.count) track(s) (was \(oldCount))")
        queue.append(contentsOf: tracks.map { QueueItem(file: $0) })
        scheduleQueueMirror()
        guard isPlaying, let current = selectedTrackIndex else { return tracks.count }
        if let armIndex = QueueAdvance.appendArmIndex(
            current: current, oldCount: oldCount, hasPending: pendingNextIndex != nil,
            shuffle: shuffleEnabled, repeatMode: repeatMode
        ) {
            armOnDeck(index: armIndex)
        }
        return tracks.count
    }

    /// Arm the gapless on-deck to `index` (or clear it) — the shared engine-arming
    /// primitive for the queue-mutation ops. It sets `pendingNextIndex` and pushes the
    /// URL to the engine, but DOES NOT call `computeNextIndex` (so it never re-rolls a
    /// shuffle pick) and DOES NOT touch `lastTransitionCount` (that baseline belongs to
    /// `startPlayback`/the transition, design §6).
    private func armOnDeck(index: Int?) {
        pendingNextIndex = index
        let url: URL? = index.flatMap { $0 >= 0 && $0 < queue.count ? queue[$0].file.absoluteURL : nil }
        Task { [weak self] in
            guard let self else { return }
            await engine.setNextTrack(url)
        }
    }
}
