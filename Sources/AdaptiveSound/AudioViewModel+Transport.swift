import Foundation

// MARK: - AudioViewModel transport (track selection / skip / press-play)

@MainActor
extension AudioViewModel {
    /// Play the track at the given playlist index. An explicit track pick, so it clears any
    /// position-preserving Pause resume point (D2) — the new track starts from 0.
    func playTrack(at index: Int) {
        guard index < playlist.count else { return }
        pausedResumePosition = nil
        selectedTrackIndex = index
        startPlayback()
    }

    /// Press-Play entry point. Three cases:
    /// - Resuming from a position-preserving Pause (`pausedResumePosition` set): restart the current
    ///   track and seek back to the paused offset (D2).
    /// - Nothing selected yet (e.g. right after loading a folder): pick the starting track — first,
    ///   or random when shuffle is on — then play from the top.
    /// - A track is already selected: (re)start it from the top.
    /// (Previously Play did nothing with no selection, so a freshly-loaded folder wouldn't start on
    /// the first Play press.)
    func play() {
        // Resume from a Pause: consume + clear the saved offset and seek back to it after start.
        if let resumeAt = pausedResumePosition {
            pausedResumePosition = nil
            startPlayback(resumeFrom: resumeAt)
            return
        }
        if selectedTrackIndex == nil {
            guard !playlist.isEmpty else { return }
            selectedTrackIndex = shuffleEnabled ? Int.random(in: 0 ..< playlist.count) : 0
        }
        startPlayback()
    }

    /// Pause playback, preserving the playhead (D2 / UI-3). Unlike `stopPlayback()`, this keeps
    /// `playbackPosition` (the scrubber stays put) and records `pausedResumePosition` so the next
    /// `play()` resumes from here via a seek. The engine has no suspend primitive, so this is a
    /// stop + resume-from-position (resume has a brief re-buffer gap), which the founder chose over
    /// a larger true-suspend engine change.
    func pause() {
        guard isPlaying else { return }
        pausedResumePosition = playbackPosition
        logUX("pause at \(secs(playbackPosition))s")
        // Clear the on-deck slot so `tickSpectrum` won't auto-advance after we stop the engine.
        pendingNextIndex = nil
        Task { await performPause() }
    }

    /// Skip to the next track, honouring shuffle + repeat (VM-2). Routes through the same
    /// `computeNextIndex` the auto-advance path uses, with `manualSkip: true` so repeat-one steps
    /// to the next track instead of repeating the current one. When shuffle is on the next track is
    /// random; repeat-all wraps at the end; with no repeat, Next on the last track is a no-op.
    /// If currently playing, switches the ENGINE to the new track (startPlayback re-arms the gapless
    /// on-deck); if paused, just re-selects. (Previously Next/Prev were LINEAR and ignored
    /// shuffle/repeat, and only moved `selectedTrackIndex` while the audio kept playing the old
    /// track.)
    func nextTrack() {
        guard let current = selectedTrackIndex else { return }
        guard let next = computeNextIndex(current: current, playlistCount: playlist.count,
                                          manualSkip: true) else { return }
        pausedResumePosition = nil // explicit track change: don't resume the old paused offset
        selectedTrackIndex = next
        if isPlaying { startPlayback() }
    }

    /// Skip to the previous track, honouring shuffle + repeat (VM-2). Under shuffle this is a random
    /// other track (no shuffle history is kept); repeat-all wraps to the last track; with no repeat,
    /// Previous on the first track is a no-op. Same play-if-playing semantics as `nextTrack()`.
    func previousTrack() {
        guard let current = selectedTrackIndex else { return }
        guard let previous = computePreviousIndex(current: current,
                                                  playlistCount: playlist.count) else { return }
        pausedResumePosition = nil // explicit track change: don't resume the old paused offset
        selectedTrackIndex = previous
        if isPlaying { startPlayback() }
    }
}
