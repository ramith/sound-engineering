// PlaybackQueueKit — the pure "insert a single track next + jump to it now" decision (parallels
// `QueueAdvance`, which holds the pure next/previous decisions). Extracted from
// `AudioViewModel.playTrackNextNow` so the index math is unit-testable without the engine / VM,
// and so the app + tests share the identical arithmetic (no hand-mirror to drift).
//
// Pure + `Sendable`: no @MainActor, no engine, no VM state — just index arithmetic over the
// current slot, which slots hold the track, and the queue count.

/// The pure index-remap for the Songs-list single-track "Play Next + jump" verb.
public enum QueueInsert {
    /// Resolve where to insert (and what to remove) so a single clicked track plays NOW, right
    /// after the current track, with the rest of the existing queue following. By SLOT (council C-17,
    /// N6): the queue may hold a track more than once (S10.2), so which slot holds it decides.
    ///
    /// - Parameters:
    ///   - current: the currently-playing slot, or nil when nothing is playing.
    ///   - count: the queue length (pre-removal).
    ///   - holdsTrack: whether the slot at an index holds the clicked track.
    ///
    /// Behavior:
    /// - The playing slot holds the clicked track: `.restartCurrent` — restart that slot in place, even
    ///   when an earlier slot holds the same track (no move, no churn).
    /// - Nothing playing (`current == nil`): front-insert at 0 so the existing queue follows; an
    ///   empty queue simply becomes `[track]`. The track's first slot, if queued, is removed first.
    /// - Otherwise: remove the track's first slot (if queued), then insert right after the current
    ///   track. A removal BEFORE the current index slides current down by one before the `+ 1`.
    public static func playNextNow(current: Int?, count: Int, holdsTrack: (Int) -> Bool) -> PlayNextNowMove {
        // Re-clicking the playing slot's track → restart in place (no dup, no array churn).
        if let current, current < count, holdsTrack(current) {
            return .restartCurrent(index: current)
        }
        let existing = (0 ..< count).first(where: holdsTrack)
        // A removal shrinks the queue by one; clamp the insert slot against the post-removal count.
        let postCount = existing == nil ? count : count - 1
        // Nothing playing → front-insert so the EXISTING queue follows (empty → becomes [track]).
        // Removing an earlier occurrence never moves the front slot (0).
        guard let current else {
            return .insertAndPlay(removeAt: existing, insertAt: 0)
        }
        // Removing an occurrence BEFORE current slides current down one; after / absent leaves it.
        let removedBeforeCurrent = existing.map { $0 < current } ?? false
        let adjustedCurrent = removedBeforeCurrent ? current - 1 : current
        let insertAt = min(adjustedCurrent + 1, postCount)
        return .insertAndPlay(removeAt: existing, insertAt: insertAt)
    }
}
