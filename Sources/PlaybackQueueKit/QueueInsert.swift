// PlaybackQueueKit — the pure "insert a single track next + jump to it now" decision (parallels
// `QueueAdvance`, which holds the pure next/previous/append decisions). Extracted from
// `AudioViewModel.playTrackNextNow` so the index math is unit-testable without the engine / VM,
// and so the app + tests share the identical arithmetic (no hand-mirror to drift).
//
// Pure + `Sendable`: no @MainActor, no engine, no VM state — just index arithmetic over the
// current index, the track's existing position (if any), and the queue count.

/// The pure index-remap for the Songs-list single-track "Play Next + jump" verb.
public enum QueueInsert {
    /// Resolve where to insert (and what to remove) so a single clicked track plays NOW, right
    /// after the current track, with the rest of the existing queue following.
    ///
    /// - Parameters:
    ///   - current: the currently-playing index, or nil when nothing is playing.
    ///   - existing: the track's current index in the queue, or nil when it isn't queued. (The
    ///     queue forbids duplicate URLs, so there is at most one occurrence.)
    ///   - count: the current queue length (pre-removal), used only to clamp the insert slot
    ///     defensively — mirrors `playNext`'s `min(current + 1, playlist.count)`.
    ///
    /// Behavior:
    /// - Re-clicking the current track (`existing == current`): `.restartCurrent` — restart in
    ///   place, no dup, no churn.
    /// - Nothing playing (`current == nil`): front-insert at 0 so the existing queue follows; an
    ///   empty queue simply becomes `[track]`. An already-queued occurrence is removed first.
    /// - Otherwise: remove any existing occurrence, then insert right after the current track. A
    ///   removal BEFORE the current index slides current down by one before the `+ 1`.
    public static func playNextNow(current: Int?, existing: Int?, count: Int) -> PlayNextNowMove {
        // Re-clicking the currently-playing track → restart in place (no dup, no array churn).
        if let current, let existing, existing == current {
            return .restartCurrent(index: current)
        }
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
