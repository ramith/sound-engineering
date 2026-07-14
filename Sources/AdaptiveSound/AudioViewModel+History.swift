import Foundation

// MARK: - AudioViewModel session play-history (S10.2 3a)

//
// The queue panel's "History" tab: an append-only log of tracks played THIS session. Distinct
// from the queue (Up Next) and from the persistent "current" playlist — it is a session record,
// never mirrored to the store and never persisted across relaunch (founder §3a). Clear Queue does
// NOT touch it.

@MainActor
extension AudioViewModel {
    /// Append a freshly-started track to the session play-history. Called at the two points where
    /// a track BEGINS a genuine new play: a manual start (`startPlayback`, only when `resumeFrom`
    /// is nil, so a pause→resume of the same track never spams the log) and the gapless
    /// auto-advance seam (`handleTrackTransition`). Dups allowed (re-playing logs again).
    func recordPlayStart(_ file: AudioFile) {
        sessionHistory.append(HistoryItem(file: file))
    }

    /// Play a History entry NOW (founder: History tap = "play it now"). Routes through
    /// `playTrackNextNow`, so the track plays immediately while the rest of the queue is preserved
    /// (and, if it's already queued, its first occurrence is moved rather than duplicated) — the
    /// same non-destructive jump-play the Songs list uses.
    func playFromHistory(_ item: HistoryItem) {
        logUX("playFromHistory: '\(item.file.name)'")
        playTrackNextNow(item.file)
    }
}
