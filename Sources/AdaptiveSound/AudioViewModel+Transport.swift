import Foundation
import PlaybackQueueKit

// MARK: - AudioViewModel transport (track selection / skip / press-play)

@MainActor
extension AudioViewModel {
    /// Read-only view of the queue as plain `AudioFile`s, for cold display consumers that don't
    /// need slot identity (menu-bar, now-playing widget, transport). Queue *edits* go through the
    /// `queue`-mutating verbs; this shim just keeps the many read sites working unchanged.
    var playlist: [AudioFile] {
        queue.map(\.file)
    }

    /// The queue slot of the selected song (`nil` = none, or an index out of range).
    var selectedSlotID: UUID? {
        selectedTrackIndex.flatMap { $0 >= 0 && $0 < queue.count ? queue[$0].id : nil }
    }

    /// Where Play resumes the selected song: the resume point when it belongs to the selected slot.
    /// `nil` means "not paused" (the scrubber and Now Playing read it as such).
    var pausedResumePosition: Double? {
        resumePoint?.seconds(resuming: selectedSlotID)
    }

    /// Whether a manual Next would advance (honors shuffle / repeat / end-of-queue) — the single
    /// source of truth with `nextTrack()`, used for the remote command's `.isEnabled` (S10.4).
    var canGoNext: Bool {
        // No selection → `nextTrack()` no-ops, so Next must read as disabled too (single source of
        // truth with the verb — S10.4 CG-4; matches `canGoPrevious`).
        guard let current = selectedTrackIndex else { return false }
        return computeNextIndex(current: current, playlistCount: queue.count, manualSkip: true) != nil
    }

    /// Whether a manual Previous would move — mirrors `previousTrack()`. Under shuffle at a pass's first
    /// song a press restarts the song, so it is enabled.
    var canGoPrevious: Bool {
        guard let current = selectedTrackIndex else { return false }
        return computePreviousIndex(current: current, playlistCount: queue.count) != nil
    }

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
    /// to the next track instead of repeating the current one. Under shuffle it is the pass's next song
    /// (R1.1-B) — at the pass's end a new pass with Repeat All, nothing with Repeat off; in order,
    /// repeat-all wraps at the end; with no repeat, Next on the last track is a no-op.
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

    /// Skip to the previous track, honouring shuffle + repeat (VM-2). Under shuffle it walks back through
    /// what played (R1.1-B): at the pass's first song, into the last pass with Repeat All, else the song
    /// restarts (founder, 2026-10-25). In order, repeat-all wraps to the last track; with no repeat,
    /// Previous on the first track is a no-op. Same play-if-playing semantics as `nextTrack()`.
    func previousTrack() {
        guard let current = selectedTrackIndex else { return }
        guard let previous = computePreviousIndex(current: current,
                                                  playlistCount: playlist.count) else { return }
        // A step back in the pass, not a pick: a pick would count the song as played again (+Playlist).
        shufflePass?.stepBack(repeatMode: repeatMode)
        resumePoint = nil // explicit track change: don't resume the old paused offset
        selectedTrackIndex = previous
        if playIntent {
            startPlayback()
        }
    }
}
