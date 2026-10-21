import Foundation
import PlaybackQueueKit

// MARK: - AudioViewModel transport (track selection / skip / press-play)

@MainActor
extension AudioViewModel {
    /// Play the track at the given playlist index. An explicit track pick, so it clears any
    /// position-preserving Pause resume point (D2) — the new track starts from 0.
    func playTrack(at index: Int) {
        guard index < playlist.count else { return }
        resumePoint = nil
        selectedTrackIndex = index
        startPlayback()
    }

    /// Press-Play entry point. Three cases:
    /// - Resuming from a position-preserving Pause (`pausedResumePosition` set): restart the current
    ///   track and seek back to the paused offset (D2) — or to where a scrub while paused moved it.
    /// - Nothing selected yet (e.g. right after loading a folder): pick the starting track — first,
    ///   or random when shuffle is on — then play from the top.
    /// - A track is already selected: (re)start it from the top.
    /// (Previously Play did nothing with no selection, so a freshly-loaded folder wouldn't start on
    /// the first Play press.)
    /// A start already on its way is this Play (a second press, Control Center's Play): it joins it,
    /// never starts the song again (council C-15).
    func play() {
        switch transportCommand {
        case .start, .prime: return
        case .stop, nil: break
        }
        // Resume from a Pause: consume + clear the saved offset and seek back to it after start.
        let resumeAt = pausedResumePosition
        resumePoint = nil
        if let resumeAt {
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
    /// A start on its way is paused too (council C-15): it ends, at its own place, and Play resumes
    /// there. The stop is numbered now, so a Play right after it is newer and wins.
    func pause() {
        guard playIntent else { return }
        resumePoint = selectedSlotID.map { ResumePoint(slot: $0, seconds: playbackPosition) }
        logUX("pause at \(secs(playbackPosition))s")
        // The stop takes the engine's on-deck with it.
        pendingNextIndex = nil
        let epoch = nextStopEpoch()
        work.spawn { [self] in await performPause(epoch: epoch) }
    }

    /// Position-preserving transport toggle — the single entry point every UI play/pause control
    /// (footer, Controls menu, queue, menu bar) routes through, so the behaviour can't drift between
    /// them. `pause()` keeps the playhead; `play()` resumes from it. It follows what the user last
    /// asked (`playIntent`), so a second press during a start pauses it, and one during a pause plays.
    func togglePlayPause() {
        if playIntent {
            pause()
        } else {
            play()
        }
    }

    /// Skip to the next track, honouring shuffle + repeat (VM-2). Routes through the same
    /// `computeNextIndex` the auto-advance path uses, with `manualSkip: true` so repeat-one steps
    /// to the next track instead of repeating the current one. When shuffle is on the next track is
    /// random; repeat-all wraps at the end; with no repeat, Next on the last track is a no-op.
    /// If currently playing — or starting (council C-15) — switches the ENGINE to the new track
    /// (startPlayback re-arms the gapless on-deck); if paused, just re-selects. (Previously Next/Prev
    /// were LINEAR and ignored shuffle/repeat, and only moved `selectedTrackIndex` while the audio kept
    /// playing the old track.)
    func nextTrack() {
        guard let current = selectedTrackIndex else { return }
        guard let next = computeNextIndex(current: current, playlistCount: playlist.count,
                                          manualSkip: true) else { return }
        resumePoint = nil // explicit track change: don't resume the old paused offset
        selectedTrackIndex = next
        if playIntent {
            startPlayback()
        }
    }

    /// Skip to the previous track, honouring shuffle + repeat (VM-2). Under shuffle this is a random
    /// other track (no shuffle history is kept); repeat-all wraps to the last track; with no repeat,
    /// Previous on the first track is a no-op. Same play-if-playing semantics as `nextTrack()`.
    func previousTrack() {
        guard let current = selectedTrackIndex else { return }
        guard let previous = computePreviousIndex(current: current,
                                                  playlistCount: playlist.count) else { return }
        resumePoint = nil // explicit track change: don't resume the old paused offset
        selectedTrackIndex = previous
        if playIntent {
            startPlayback()
        }
    }
}
