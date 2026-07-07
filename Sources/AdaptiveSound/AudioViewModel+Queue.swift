import Foundation
import PlaybackQueueKit

// MARK: - AudioViewModel queue ops (S9-Q2 — Play Now / Play Next / Add to Queue / jump-play)

//
// The browse UI's play verbs, layered on the existing index-addressed engine
// (playlist: [AudioFile] + selectedTrackIndex + the gapless on-deck pendingNextIndex).
// Callers convert LibraryTrackDisplay → AudioFile (see AudioFile+LibraryTrackDisplay).
// `playTrackNextNow` is the Songs-list single-track "insert after current + jump to play NOW".
//
// The pure DECISIONS live in PlaybackQueueKit, shared by the tests: whether an append re-arms
// the on-deck is `QueueAdvance.appendArmIndex`; the single-track jump-play index-remap
// (remove/insert slots + the current-index shift) is `QueueInsert.playNextNow`. The rest here
// is mechanical array + engine sequencing.
//
// SCOPE (per the S9-Q2 decision — the per-entry-id queue wrapper is deferred to S10):
// a queue entry's identity is its URL (AudioFile.id == absoluteURL), and the id-keyed
// PlaylistView ForEach can't render duplicate ids. So these verbs DEDUPE-ON-ADD (a track
// already queued is not re-added) — the interim contract until S10's wrapper enables
// intentional duplicates + the id-safe `movePlaylistItems` reorder ("queue reorder/save/
// history" is S10 scope; movePlaylistItems is intentionally untouched here).

@MainActor
extension AudioViewModel {
    /// Replace the queue with `tracks` and start playing from `startAt` (clamped).
    /// The destructive "play this album/these results now" action. `startPlayback`
    /// (via `playTrack`) re-primes the gapless on-deck.
    func playNow(_ tracks: [AudioFile], startAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        let start = min(max(0, index), tracks.count - 1)
        logUX("playNow: \(tracks.count) track(s), startAt=\(start)")
        playlist = tracks
        playTrack(at: start)
    }

    /// Insert `tracks` immediately after the current track and arm the first of them as
    /// the on-deck — a single-slot override honored EVEN under shuffle (Music.app's
    /// "Play Next"), because it sets `pendingNextIndex` directly rather than routing
    /// through `computeNextIndex` (design §6; the multi-item forced-next FIFO is S10).
    /// With nothing playing there is no "current" to insert after, so it appends.
    func playNext(_ tracks: [AudioFile]) {
        let tracks = dedupedAgainstQueue(tracks)
        guard !tracks.isEmpty else { return }
        guard let current = selectedTrackIndex else {
            appendToQueue(tracks) // nothing selected → no "current" to insert after
            return
        }
        let insertAt = min(current + 1, playlist.count)
        logUX("playNext: \(tracks.count) track(s) after index \(current) (playing=\(isPlaying))")
        playlist.insert(contentsOf: tracks, at: insertAt)
        // Playing → arm the inserted slot as the on-deck (single-slot override, honors
        // shuffle). Paused → the insert alone plays it next under LINEAR order (resume's
        // primeGaplessPipeline derives computeNextIndex(current) = current+1); the
        // shuffle-while-paused case is best-effort until the S10 forced-next queue.
        if isPlaying { armOnDeck(index: insertAt) }
    }

    /// Insert `track` immediately after the current track and JUMP to play it NOW — the Songs-list
    /// double-click / Return / single-row "Play". Unlike `playNext` (which only ARMS the on-deck),
    /// this routes through `playTrack(at:)`, so the engine restarts on the inserted slot and
    /// `primeGaplessPipeline` re-primes the on-deck; the rest of the EXISTING queue follows after.
    ///
    /// The queue forbids duplicate URLs (until S10 — a dup breaks `PlaylistView`'s id-keyed
    /// `ForEach`), so if `track` is already queued its existing occurrence is REMOVED before the
    /// insert (a MOVE, not a copy). The pure index-remap — remove/insert slots and the
    /// current-index shift when the removed occurrence was before current — is
    /// `QueueInsert.playNextNow`, shared by the tests.
    ///
    /// Edge cases:
    /// - Nothing playing (`selectedTrackIndex == nil`): front-insert (index 0) so the existing
    ///   queue follows; an empty queue simply becomes `[track]`.
    /// - Re-clicking the currently-playing track: RESTART it in place — a jump-play of the current
    ///   track restarts from the top (no dup, no array churn, no on-deck disturbance).
    ///
    /// No play-count increment is routed here: a jump-play is not a natural completion, so
    /// play-tracking (S10) stays a separate change.
    func playTrackNextNow(_ track: AudioFile) {
        let move = QueueInsert.playNextNow(
            current: selectedTrackIndex,
            existing: playlist.firstIndex { $0.id == track.id },
            count: playlist.count
        )
        switch move {
        case let .restartCurrent(index):
            logUX("playTrackNextNow: restart current index \(index) '\(track.name)'")
            playTrack(at: index)
        case let .insertAndPlay(removeAt, insertAt):
            if let removeAt { playlist.remove(at: removeAt) }
            playlist.insert(track, at: insertAt)
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
    func appendToQueue(_ tracks: [AudioFile]) {
        let tracks = dedupedAgainstQueue(tracks)
        guard !tracks.isEmpty else { return }
        let oldCount = playlist.count
        logUX("appendToQueue: \(tracks.count) track(s) (was \(oldCount))")
        playlist.append(contentsOf: tracks)
        guard isPlaying, let current = selectedTrackIndex else { return }
        if let armIndex = QueueAdvance.appendArmIndex(
            current: current, oldCount: oldCount, hasPending: pendingNextIndex != nil,
            shuffle: shuffleEnabled, repeatMode: repeatMode
        ) {
            armOnDeck(index: armIndex)
        }
    }

    /// Arm the gapless on-deck to `index` (or clear it) — the shared engine-arming
    /// primitive for the queue-mutation ops. It sets `pendingNextIndex` and pushes the
    /// URL to the engine, but DOES NOT call `computeNextIndex` (so it never re-rolls a
    /// shuffle pick) and DOES NOT touch `lastTransitionCount` (that baseline belongs to
    /// `startPlayback`/the transition, design §6).
    private func armOnDeck(index: Int?) {
        pendingNextIndex = index
        let url: URL? = index.flatMap { $0 >= 0 && $0 < playlist.count ? playlist[$0].absoluteURL : nil }
        Task { [weak self] in
            guard let self else { return }
            await engine.setNextTrack(url)
        }
    }

    /// Drop input tracks whose URL is already queued (and within-batch duplicates). Until
    /// the S10 per-entry-id wrapper, a queue entry's identity IS its URL (`AudioFile.id ==
    /// absoluteURL`), so a duplicate would break `PlaylistView`'s id-keyed `ForEach`.
    /// Dedupe-on-add is the interim contract; S10's wrapper will allow intentional dups.
    private func dedupedAgainstQueue(_ tracks: [AudioFile]) -> [AudioFile] {
        var seen = Set(playlist.map(\.id))
        return tracks.filter { seen.insert($0.id).inserted }
    }
}
