import AVFoundation
import Foundation

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

// MARK: - Next-Index Computation (internal — consumed by tests via local mirror)

extension AudioViewModel {
    /// Compute the playlist index that should play after `current`, honouring
    /// `shuffleEnabled` and `repeatMode`.
    ///
    /// - Returns: the next index, or `nil` when playback should stop after `current`.
    func computeNextIndex(current: Int, playlistCount: Int) -> Int? {
        guard playlistCount > 0 else { return nil }
        if repeatMode == 2 { return current } // repeat-one

        if shuffleEnabled, playlistCount > 1 {
            var candidate = Int.random(in: 0 ..< playlistCount)
            while candidate == current {
                candidate = Int.random(in: 0 ..< playlistCount)
            }
            return candidate
        }

        let nextLinear = current + 1
        if nextLinear < playlistCount { return nextLinear }
        return repeatMode == 1 ? 0 : nil
    }
}
