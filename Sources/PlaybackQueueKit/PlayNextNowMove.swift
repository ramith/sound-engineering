// PlaybackQueueKit — the pure result of a "play this track next + jump to it now" decision.
//
// Companion to `QueueInsert.playNextNow` (see QueueInsert.swift). Kept in its own file (one type
// per file) and pure + `Sendable` so the decision is unit-testable without the engine / VM.

/// The array move a single-track "Play Next + jump" resolves to, computed by
/// `QueueInsert.playNextNow`. The queue forbids duplicate URLs (until S10), so an already-queued
/// track is MOVED (removed, then re-inserted) rather than duplicated.
public enum PlayNextNowMove: Equatable, Sendable {
    /// The clicked track IS the currently-playing track — restart it in place at `index`; no array
    /// mutation (avoids needless dedup remove/re-insert churn). The on-deck is re-primed like any
    /// restart (a no-op under linear order; a fresh pick under shuffle).
    case restartCurrent(index: Int)

    /// Remove the track's existing queued occurrence at `removeAt` (nil when it isn't queued), then
    /// insert it at `insertAt` and jump-play that slot. `insertAt` already accounts for the removal
    /// shift: a removal BEFORE the current track slid current down by one before the `+ 1`.
    case insertAndPlay(removeAt: Int?, insertAt: Int)
}
