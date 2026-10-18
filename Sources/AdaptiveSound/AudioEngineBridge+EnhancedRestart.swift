@preconcurrency import AVFoundation
import Foundation
import PlaybackQueueKit

// MARK: - AudioEngineBridge: the one Enhanced "play from a place" (council C-25, DUP-1)

/// Every Enhanced playback that starts somewhere goes through here: a start (`playFile`, from the top
/// or a resume point), a seek, a re-establish after a device change. Before R1.1 there were three
/// copies of it, and they disagreed: the start clamped, the seeks silently ignored an out-of-range
/// place, one rounded and the others truncated, a NaN trapped, and the seek moved the playhead
/// before it knew it would succeed — so a seek to the end of any non-48 kHz track was refused after
/// abandoning the resampler's chain, and the music stopped for good (KI-PB-18).
///
/// Now:
/// - **One rule** places the request (`SeekTarget`): finite first, nothing before 0, the nearest
///   frame, and a frame at or past the end is `.end` — the track ends now, through the end-of-track
///   path, as if it had played out.
/// - **Prepare, then commit.** Preparing opens the file, places the request and picks the route
///   (passthrough, or a new resampler); it touches nothing, so a seek that can't prepare leaves
///   playback exactly as it was. Committing supersedes what the player had scheduled, then either
///   ends the track or moves the position base to the frame it plays from and schedules from there.
///   The position base moves only here.
/// - **One schedule completion** for the passthrough sub-path (`passthroughEndOfTrack`), shared with
///   the gapless seams.
///
/// What stays the caller's: a start (`playFile`) is a new playback, so it clears the previous one's
/// seam hooks first; a seek or re-establish is the same playback at a new place, so the on-deck track
/// and its hook stay armed. The rest of the transport rework (one owner of the frame timeline, the
/// seams counted in frames) is the Engine sprint's.
extension AudioEngineBridge {
    /// What playing from a place did.
    enum EnhancedRestart: Equatable {
        /// Playing from this place (seconds into the file: the frame it landed on).
        case playing(from: Double)
        /// The place was at or past the end: the track ended now. The end flag is up, so the view
        /// model advances — or stops at the end of the queue — as at any end.
        case ended
        /// Nothing changed: the place was not a number, or the file would not open.
        case unchanged
    }

    /// How a file reaches the player.
    enum EnhancedRoute {
        /// At the graph's rate: the file's frames go straight to the player.
        case passthrough
        /// Off the graph's rate: streamed through the Mastering resampler.
        case resampler(EnhancedResampleSession)
        /// Off the graph's rate with no converter to be had: the player's own, lower-quality
        /// conversion plays it rather than nothing. (Apple's converter exists for every format
        /// `AVAudioFile` decodes, so this is a guard, not a path anyone hears.)
        case playerConversion

        /// For the log lines.
        func label(fileRate: Double, graphRate: Double) -> String {
            switch self {
            case .passthrough:
                "\(Int(graphRate)) passthrough"
            case .resampler:
                "resample \(Int(fileRate))→\(Int(graphRate)) mastering"
            case .playerConversion:
                "resample \(Int(fileRate))→\(Int(graphRate)) FELL BACK to the player's conversion"
            }
        }
    }

    // MARK: - Restart (a seek, a re-establish)

    /// Play the current file (`lastFileURL`) from `seconds` — the same playback at a new place: a seek
    /// or a re-establish after a device change. Its on-deck track and seam hook stay armed. Runs on
    /// `engineQueue` or `configChangeQueue` (never `resampleQueue`).
    func restartEnhanced(at seconds: Double, player: AVAudioPlayerNode) -> EnhancedRestart {
        guard let url = lastFileURL else { return .unchanged }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        // Prepare: nothing changes unless the file opens and the request is a place in it.
        guard let file = try? AVAudioFile(forReading: url),
              let target = SeekTarget(seconds: seconds, length: file.length,
                                      sampleRate: file.processingFormat.sampleRate)
        else { return .unchanged }
        return commitEnhanced(file, route: enhancedRoute(for: file, player: player), at: target,
                              player: player)
    }

    // MARK: - Prepare

    /// How `file` reaches `player`: through, at the graph's rate; otherwise through a new resampler
    /// session to the player's current format. Touches no playback state.
    func enhancedRoute(for file: AVAudioFile, player: AVAudioPlayerNode) -> EnhancedRoute {
        let outputFormat = player.outputFormat(forBus: 0)
        guard file.processingFormat.sampleRate != outputFormat.sampleRate else { return .passthrough }
        guard let session = EnhancedResampleSession(file: file, outputFormat: outputFormat) else {
            return .playerConversion
        }
        return .resampler(session)
    }

    // MARK: - Commit

    /// Play `file` from `target` on `route` — the commit every Enhanced start and restart shares.
    /// Supersedes what the player had scheduled (both epochs first, so every completion `stop()`
    /// fires and every in-flight chunk abandons), then either ends the track now, or moves the
    /// position base to the frame and schedules from it. Off `resampleQueue` (`engineQueue` /
    /// `configChangeQueue`): it syncs onto it.
    func commitEnhanced(_ file: AVAudioFile, route: EnhancedRoute, at target: SeekTarget,
                        player: AVAudioPlayerNode) -> EnhancedRestart {
        guard case let .frame(frame) = target else {
            endEnhancedTrackNow(player: player, reason: "a place at or past the end")
            return .ended
        }
        let epoch = supersedeAndStop(player)
        let rate = file.processingFormat.sampleRate
        // The player's sampleTime restarts at 0 on play(), so the base is where the file plays from
        // (`liveEnhancedPosition` adds it back): the frame actually played, not the request.
        let from = Double(frame) / rate
        setEnhancedPositionBaseSeconds(from)
        switch route {
        case .passthrough, .playerConversion:
            player.scheduleSegment(file, startingFrame: frame, frameCount: AVAudioFrameCount(file.length - frame),
                                   at: nil, completionCallbackType: player.playedBackCallbackType,
                                   completionHandler: passthroughEndOfTrack(epoch: epoch, player: player))
        case let .resampler(session):
            let primed = resampleQueue.sync {
                primeEnhancedResamplerLocked(session: session, player: player, startFrame: frame)
            }
            guard primed > 0 else {
                // Nothing could be read or converted from a place inside the file: it can't go on.
                // End it — never a silent player that still says "playing".
                resampleQueue.sync { endEnhancedTrackNowLocked(reason: "nothing to play from \(secs(from))s") }
                return .ended
            }
        }
        player.play()
        return .playing(from: from)
    }

    /// End the current track now, through the same end as a track that played out with nothing on
    /// deck: the player stops, the end flag goes up (the view model advances or stops), the play
    /// intent goes down (a device change won't resume it), and the seam hooks go (an ended track
    /// never seams). Off `resampleQueue`.
    func endEnhancedTrackNow(player: AVAudioPlayerNode, reason: String) {
        supersedeAndStop(player)
        resampleQueue.sync { endEnhancedTrackNowLocked(reason: reason) }
    }

    /// The end, once the player is stopped. MUST be called on `resampleQueue`.
    private func endEnhancedTrackNowLocked(reason: String) {
        stopEnhancedResamplerLocked()
        markGaplessPlaybackEnded(reason: reason)
    }

    /// Stop what the player has scheduled, in the one safe order: the epochs first (and the resampler
    /// session dropped), so every completion `player.stop()` fires and every in-flight chunk abandons
    /// instead of rolling a seam; then the stop. Returns the new passthrough epoch, for the schedule
    /// that replaces the old one. Off `resampleQueue`.
    @discardableResult
    private func supersedeAndStop(_ player: AVAudioPlayerNode) -> UInt64 {
        let epoch = resampleQueue.sync { supersedeEnhancedScheduleLocked() }
        player.stop()
        return epoch
    }

    // MARK: - The passthrough schedule's completion

    /// The completion of a passthrough schedule installed under passthrough `epoch`: once the file has
    /// been heard (`playedBackCallbackType`) it hops to `resampleQueue` and runs the end-of-track path
    /// (`firePassthroughEOFOrEnd`: the seam, or the end) — unless a later stop / seek / reschedule
    /// moved the epoch on, since `player.stop()` fires it too, indistinguishable from a real end
    /// (the wrong-song bug). The one copy of this closure (council DUP-1), for the restart's
    /// segment and the seams' files alike.
    func passthroughEndOfTrack(epoch: UInt64, player: AVAudioPlayerNode)
        -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        { [weak self, weak player] _ in
            guard let self, let player else { return }
            self.resampleQueue.async {
                guard epoch == self.passthroughGeneration else { return } // superseded
                self.firePassthroughEOFOrEnd(player: player)
            }
        }
    }
}

// MARK: - When a schedule has been heard

extension AVAudioPlayerNode {
    /// The completion type that reports a schedule has been HEARD — what an end of track waits for,
    /// so stopping at it cuts nothing: `.dataPlayedBack`, which waits out the output's latency. An
    /// engine in manual rendering never reports that one (it has no device); there, what is rendered
    /// is the output, so it gets `.dataRendered`.
    var playedBackCallbackType: AVAudioPlayerNodeCompletionCallbackType {
        engine?.isInManualRenderingMode == true ? .dataRendered : .dataPlayedBack
    }
}
