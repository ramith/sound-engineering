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
        guard let nextIdx = pendingNextIndex else {
            logUX("trackTransition: pendingNextIndex is nil, ignoring")
            return
        }
        guard nextIdx < playlist.count else {
            logUX("trackTransition: pendingNextIndex \(nextIdx) out of range, stopping")
            pendingNextIndex = nil
            isPlaying = false
            playbackPosition = 0
            return
        }

        let advancedTrack = playlist[nextIdx]
        logUX("trackTransition: advancing to index=\(nextIdx) '\(advancedTrack.name)'")

        selectedTrackIndex = nextIdx
        playbackPosition = 0
        duration = 0 // zeroed now; async Task below refreshes from AVAudioFile

        let newNextIdx = computeNextIndex(current: nextIdx, playlistCount: playlist.count)
        pendingNextIndex = newNextIdx

        let fileURL = advancedTrack.absoluteURL
        let pureModeSnap = pureModeEnabled

        Task.detached(priority: .userInitiated) { [weak self] in
            let computedDuration: Double = {
                guard let file = try? AVAudioFile(forReading: fileURL) else { return 0 }
                let rate = file.processingFormat.sampleRate
                return rate > 0 ? Double(file.length) / rate : 0
            }()
            await MainActor.run { [computedDuration] in
                self?.duration = computedDuration
                logUX("trackTransition: duration = \(secs(computedDuration))s")
            }
        }

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
