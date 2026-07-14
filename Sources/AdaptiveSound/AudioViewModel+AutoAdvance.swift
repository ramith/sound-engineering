import AVFoundation
import Foundation
import PlaybackQueueKit

// MARK: - AudioViewModel gapless / auto-advance

@MainActor
extension AudioViewModel {
    /// Invoked when `trackTransitionCount()` increases (a gapless seam completed).
    /// Advances the highlighted index, resets the scrubber, refreshes duration,
    /// and queues the NEW next track on-deck.
    func handleTrackTransition() {
        // Pre-existing, not one of the §12.3 completion sites: a live transition-count
        // increase implies an on-deck track was armed (pendingNextIndex non-nil), so this
        // branch is structurally unreachable during normal playback — defensive, not a
        // natural-completion path, hence no play-count call here.
        guard let nextIdx = pendingNextIndex else {
            logUX("trackTransition: pendingNextIndex is nil, ignoring")
            return
        }
        guard nextIdx < playlist.count else {
            logUX("trackTransition: pendingNextIndex \(nextIdx) out of range, stopping")
            // §12.3: the track that was playing (pre-advance selectedTrackIndex) still
            // completed naturally — count it before returning (a playlist-shrank-after-
            // arming edge; the normal end-of-queue path below is what usually counts the
            // final track).
            countPlayIfNaturalEndQualifies()
            pendingNextIndex = nil
            isPlaying = false
            playbackPosition = 0
            return
        }

        let advancedTrack = playlist[nextIdx]
        logUX("trackTransition: advancing to index=\(nextIdx) '\(advancedTrack.name)'")

        // §12.3: count the OUTGOING track (pre-advance selectedTrackIndex) before it
        // reassigns below — this IS the gapless-seam natural-completion site.
        countPlayIfNaturalEndQualifies()

        selectedTrackIndex = nextIdx
        recordPlayStart(advancedTrack) // the incoming track begins playing — log it (S10.2 3a)
        resetPlayTracking() // the gapless seam / repeat-one begins a NEW ≥60% play-through (S10.6)
        playbackPosition = 0
        duration = 0 // zeroed now; async Task below refreshes from AVAudioFile

        let newNextIdx = computeNextIndex(current: nextIdx, playlistCount: playlist.count)
        pendingNextIndex = newNextIdx

        let fileURL = advancedTrack.absoluteURL
        let pureModeSnap = pureModeEnabled

        refreshDuration(for: fileURL, logLabel: "trackTransition: duration")

        Task { [weak self] in
            guard let self else { return }
            if let newIdx = newNextIdx, newIdx < playlist.count {
                let nextURL = playlist[newIdx].absoluteURL
                await engine.setNextTrack(nextURL)
                logUX("trackTransition: primed next index=\(newIdx) pureMode=\(pureModeSnap)")
            } else {
                await engine.setNextTrack(nil)
                logUX("trackTransition: no further track to queue")
            }
        }
    }
}

// MARK: - Next-Index Computation (thin delegates to PlaybackQueueKit.QueueAdvance)

extension AudioViewModel {
    /// Compute the playlist index that should play after `current`, honouring
    /// `shuffleEnabled` and `repeatMode`.
    ///
    /// - Parameter manualSkip: `true` when the user pressed Next (vs an automatic end-of-track
    ///   advance). Under repeat-one a manual skip STEPS to the next track rather than repeating the
    ///   current one; an automatic advance repeats it. Shuffle and repeat-all behave identically
    ///   either way.
    /// - Returns: the next index, or `nil` when playback should stop / stay after `current`.
    func computeNextIndex(current: Int, playlistCount: Int, manualSkip: Bool = false) -> Int? {
        QueueAdvance.nextIndex(
            current: current, count: playlistCount, shuffle: shuffleEnabled,
            repeatMode: repeatMode, manualSkip: manualSkip,
            randomPick: QueueAdvance.uniformRandomExcluding
        )
    }

    /// Compute the playlist index that should play BEFORE `current` (the Previous button).
    /// Honours `shuffleEnabled` (a random other track, since no shuffle history is kept) and
    /// `repeatMode` (repeat-all wraps to the last track). Previous is always a manual action, so
    /// repeat-one steps back rather than repeating.
    ///
    /// - Returns: the previous index, or `nil` when there is nowhere to go back to (first track,
    ///   no repeat) so the caller should stay put.
    func computePreviousIndex(current: Int, playlistCount: Int) -> Int? {
        QueueAdvance.previousIndex(
            current: current, count: playlistCount, shuffle: shuffleEnabled,
            repeatMode: repeatMode, randomPick: QueueAdvance.uniformRandomExcluding
        )
    }
}
