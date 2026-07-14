import Foundation
import LibraryStore

// MARK: - AudioViewModel play-tracking (S9.5 §12.3 — pulled forward from S10)

@MainActor
extension AudioViewModel {
    /// Count the OUTGOING track — the one at `selectedTrackIndex` right now, BEFORE any
    /// reassignment at the call site — as a natural-completion play. A no-op if
    /// `selectedTrackIndex` is nil or stale (out of range, e.g. the playlist shrank).
    ///
    /// Shared by all FOUR completion sites (`AudioViewModel+AutoAdvance`'s
    /// `handleTrackTransition` normal path + its out-of-range guard, and
    /// `AudioViewModel+SpectrumTimer`'s `tickTransport` reconfigure + end-of-queue
    /// branches) so none of their call sites' own guard adds to that function's
    /// cyclomatic complexity.
    func countOutgoingTrackCompletion() {
        guard let completedIdx = selectedTrackIndex, completedIdx < queue.count else { return }
        countPlayCompletion(file: queue[completedIdx].file)
    }

    /// Count a natural-completion play for the track at `url`: fires a detached,
    /// fire-and-forget write to the persistent store's `play_count`/`last_played`
    /// columns (`LibraryStore.incrementPlayCount`).
    ///
    /// Invoked (via `countOutgoingTrackCompletion()` above) at all FOUR natural-completion
    /// sites (the gapless seam in `handleTrackTransition`, its out-of-range guard, the Pure
    /// reconfigure advance, and the true end-of-queue branch in `tickTransport`) — NEVER from
    /// a manual skip/jump (`nextTrack`/`previousTrack`/`playTrack`/`playTrackNextNow`/
    /// `playNext`/`startPlayback` are all deliberately excluded, per the pre-change review:
    /// "a play = heard through").
    ///
    /// Errors (including "store not ready yet" and a write failure) are swallowed via
    /// `logUX`, never thrown — a play-count write must never stall or fail the audio path.
    ///
    /// S3 F5: this is the ONE audio→library edge — it reaches the store through the injected
    /// `library` peer (`library?.store`) rather than owning the store itself.
    private func countPlayCompletion(file: AudioFile) {
        guard let store = library?.store else {
            logUX("countPlayCompletion: store not ready; skipping play-count for \(file.absoluteURL.lastPathComponent)")
            return
        }
        let playedAt = Int64(Date().timeIntervalSince1970)
        let trackID = file.trackID
        let url = file.absoluteURL
        Task.detached(priority: .utility) {
            do {
                // Prefer the durable id (S10.2 — the queue carries it, no url→id lookup);
                // fall back to url for a slot with no library row.
                if let trackID {
                    try await store.incrementPlayCount(id: trackID, playedAt: playedAt)
                } else {
                    try await store.incrementPlayCount(url: url, playedAt: playedAt)
                }
            } catch {
                logUX("countPlayCompletion: write failed for \(url.lastPathComponent) — \(error)")
            }
        }
    }
}
