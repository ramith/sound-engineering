import Foundation
import LibraryStore

// MARK: - AudioViewModel play-tracking (S9.5 §12.3 → S10.6 ≥60%-heard rule)

@MainActor
extension AudioViewModel {
    /// Accrue play-through time for the current track (S10.6 R1/FIX-3). Called EVERY transport tick:
    /// it advances the monotonic reference unconditionally (so a pause/stall doesn't later read as
    /// one huge delta), but feeds a delta to the tracker only while actually playing. When the
    /// accrual first crosses the qualifying threshold (≥ min(60%·duration, 240s), ≥30s track), the
    /// current track's play is recorded — once per play-through. Seeks add ~0 wall-time between
    /// ticks, so they don't accrue; a UI-tick stall's delta IS real playtime and accrues.
    func accruePlayThrough() {
        let now = DispatchTime.now().uptimeNanoseconds // suspend-stopping (excludes system sleep)
        defer { lastPlayThroughMonoNanos = now }
        guard let last = lastPlayThroughMonoNanos else { return } // first tick: just seed
        guard isPlaying, duration > 0 else { return } // accrue only genuine playback
        let delta = Double(now &- last) / 1_000_000_000
        if playThroughTracker.accrue(delta, duration: duration) {
            countCurrentPlay()
        }
    }

    /// Begin a new play-through: clear the accrued heard-time + the once-per-play-through guard and
    /// reseed the monotonic reference. Called at exactly the two "new play begins" points — a fresh
    /// `startPlayback` (not a pause-resume) and the gapless `handleTrackTransition` (incl. a
    /// repeat-one re-arm, so each repeat can count again).
    func resetPlayTracking() {
        playThroughTracker.reset()
        lastPlayThroughMonoNanos = nil
    }

    /// Count the CURRENT track (`selectedTrackIndex`) as a play. Invoked from the tick accrual (on
    /// threshold crossing) and from the natural-end gate below. A no-op if the selection is nil or
    /// stale (out of range).
    func countCurrentPlay() {
        guard let index = selectedTrackIndex, index < queue.count else { return }
        writePlayCount(file: queue[index].file)
    }

    /// A track reached its natural end (the four completion sites): count it ONLY if it qualifies by
    /// the SAME ≥60%/≥30s gate as the tick path (FIX-1) — so a scrub-to-end or a short/unresolved-
    /// duration track does NOT count. Idempotent: if the tick path already counted this play-through
    /// (`didCount`), this is a no-op. `selectedTrackIndex`/`duration` still refer to the just-
    /// finished track at every call site (they reassign AFTER).
    func countPlayIfNaturalEndQualifies() {
        guard playThroughTracker.naturalEnd(duration: duration) else { return }
        countCurrentPlay()
    }

    /// Fire the detached, fire-and-forget play-count write (`play_count`/`last_played` + the S10.6
    /// frecency `score`/`rank` — `LibraryStore.incrementPlayCount`), then bump `playCountRevision`
    /// on the main actor AFTER the write commits (R4 — the Recently-Played view refreshes on it, so
    /// the bump must not race the write). Errors are swallowed via `logUX`, never thrown — a
    /// play-count write must never stall or fail the audio path.
    ///
    /// S3 F5: the ONE audio→library edge — reaches the store through the injected `library` peer.
    private func writePlayCount(file: AudioFile) {
        guard let store = library?.store else {
            logUX("writePlayCount: store not ready; skipping play-count for \(file.absoluteURL.lastPathComponent)")
            return
        }
        let playedAt = Int64(Date().timeIntervalSince1970)
        let trackID = file.trackID
        let url = file.absoluteURL
        Task.detached(priority: .utility) { [weak self] in
            do {
                // Prefer the durable id (the queue carries it, no url→id lookup); fall back to url.
                if let trackID {
                    try await store.incrementPlayCount(id: trackID, playedAt: playedAt)
                } else {
                    try await store.incrementPlayCount(url: url, playedAt: playedAt)
                }
                await MainActor.run { self?.playCountRevision += 1 }
            } catch {
                logUX("writePlayCount: write failed for \(url.lastPathComponent) — \(error)")
            }
        }
    }
}
