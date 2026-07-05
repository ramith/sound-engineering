import Foundation
import PlaybackQueueKit

// MARK: - AudioViewModel queue ops (S9-Q2 — Play Now / Play Next / Add to Queue)

//
// The browse UI's three play verbs, layered on the existing index-addressed engine
// (playlist: [AudioFile] + selectedTrackIndex + the gapless on-deck pendingNextIndex).
// Callers convert LibraryTrackDisplay → AudioFile (see AudioFile+LibraryTrackDisplay).
//
// The pure DECISION (whether an append re-arms the on-deck) lives in
// PlaybackQueueKit.QueueAdvance.appendArmIndex, shared by the tests; the rest here is
// mechanical array + engine sequencing.
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
