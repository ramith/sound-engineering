import AVFoundation
import Foundation
import OutputDeviceKit
import PlaybackQueueKit

// MARK: - AudioViewModel: the transport tick

@MainActor
extension AudioViewModel {
    /// Whether the transport tick has anything to follow: a song plays, or a start, a pause or a stop
    /// is on its way to the engine (council C-52). Paused or stopped, nothing moves — the engine's own
    /// clock stops too (`AudioEngineBridge+TransportClock`) — so the tick sleeps; a device change, an
    /// intent, a scrub while paused reach the screen through their own paths, not a poll.
    var transportTickIsLive: Bool {
        transportTickArmed && (isPlaying || transportCommand != nil)
    }

    /// From engine-ready (`initializeEngine`): the tick may run. One tick now settles the readouts
    /// (the EQ's design rate, the signal path) the engine came up with; then it runs whenever
    /// something plays.
    func armTransportTick() {
        transportTickArmed = true
        tickTransport()
        runTransportTickIfLive()
    }

    /// At shutdown, and in tests that tick by hand: no tick runs from here on.
    func disarmTransportTick() {
        transportTickArmed = false
        transportTicker?.stop()
        transportTicker = nil
    }

    /// Start the 20 Hz transport tick if something plays or is on its way. Called whenever that may
    /// have changed (`isPlaying`, `transportCommand`). The tick stops itself: the tick that finds
    /// nothing live is the last, after it has read the settled engine once more.
    func runTransportTickIfLive() {
        guard transportTicker == nil, transportTickIsLive else { return }
        transportTicker = makeTicker(1.0 / 20.0) { [weak self] in
            self?.tickTransport()
        }
    }

    /// Called at 20 Hz on the main thread by the transport timer while something plays or is on its
    /// way. Polls the playhead, loudness, and signal path, handles device-loss, and drives gapless
    /// auto-advance. Never touches the live spectrum — the visuals draw on their own clock (VM-3), so
    /// whether one shows can never stall transport or auto-advance.
    func tickTransport() {
        // The engine's state in ONE copy (the transport as its clock last sampled it, the signal
        // path, the loudness, the EQ design rate), so the tick never waits on the player or the
        // hardware (the disconnect freeze, S10.8 G).
        let snapshot = engine.snapshot()
        // A sample older than the latest start / seek / stop describes the playback that request
        // replaces: neither its playhead nor its end flag is acted on (MAJOR-1, S10.8 G review).
        let transport: TransportSnapshot? =
            snapshot.transport.isCurrent(for: transportEpoch) ? snapshot.transport : nil
        // Poll the playhead + loudness + signal path every tick.
        placePlayhead(transport)
        // S10.6: accrue ≥60%-heard play-through time (advances the monotonic reference every tick;
        // accrues only while playing → a pause/stall/seek never mis-counts).
        accruePlayThrough()
        pollEngineReadouts(snapshot)

        // The output device disappeared (e.g. headphones switched off) and the engine paused — a
        // real pause, like `pause()`: the song's place is kept (the last playhead read while it
        // played; the engine reports none once its device is gone), the footer and duration stay,
        // and Play resumes there on the output the pill now shows, through the normal start (Pure
        // or Enhanced decided again for that device). Nothing resumes it but Play (founder: pause
        // on disconnect, never auto-jump).
        if signalPath.interrupted,
           let resumeAt = OutputDevicePolicy.resumeAfterDeviceLoss(
               isPlaying: isPlaying, lastPlayhead: playbackPosition, duration: duration
           ) {
            logUX("device-loss interrupt — paused at \(secs(resumeAt))s")
            resumePoint = selectedSlotID.map { ResumePoint(slot: $0, seconds: resumeAt) }
            isPlaying = false
            errorMessage = "Output device disconnected — playback paused. Press Play to continue."
            // Clear pending on-deck track; device loss invalidates the gapless queue.
            armOnDeck(index: nil)
        }

        // --- Gapless auto-advance poll ---
        // Only while nothing is on its way (council C-15): a start or a stop replaces the playback
        // whose seam or end the engine reports, and a start's prime sets the seam baseline of its own
        // (a Pause in the last tick of a song used to end the queue — P4-7).
        if isPlaying, transportCommand == nil, let transport {
            let currentCount = transport.transitionCount
            if currentCount > lastTransitionCount {
                // A gapless seam completed: the on-deck track is now current.
                // Intentional: we advance by exactly ONE track per tick even if the count
                // jumped by more than one (e.g. two back-to-back very-short tracks in a
                // single 50 ms interval). The VM records the new baseline and calls
                // handleTrackTransition once; the next tick catches any remaining delta.
                // This keeps selectedTrackIndex in sync with pendingNextIndex at all times.
                lastTransitionCount = currentCount
                handleTrackTransition()
            } else if transport.ended {
                // Current track ended with no GAPLESS continuation. If a track is still queued
                // (a Pure-path rate/format transition that couldn't be armed for a seamless seam, or
                // a seek to the end on either path), advance to it with a fresh start — a brief,
                // honest gap. Otherwise the queue is exhausted: stop.
                if let nextIdx = pendingNextIndex, nextIdx < playlist.count {
                    logUX("playbackEnded — advancing to queued track[\(nextIdx)] (reconfigure gap)")
                    // §12.3: count the OUTGOING track (pre-advance selectedTrackIndex) before it
                    // reassigns below — the Pure cross-rate reconfigure natural-completion site.
                    countPlayIfNaturalEndQualifies()
                    selectedTrackIndex = nextIdx
                    // Clear the trigger SYNCHRONOUSLY before the async startPlayback: the end flag
                    // stays true until startPlayback's Task runs `pureModeEngineStart` (≤ a few ticks
                    // on a DAC reconfigure), so without this the next 20 Hz tick would re-enter and
                    // launch a second `startAudio` that interrupts B mid-startup. startPlayback
                    // re-derives pendingNextIndex inside its Task, so nothing is lost.
                    pendingNextIndex = nil
                    startPlayback()
                } else {
                    logUX("playbackEnded — no next track, stopping")
                    // §12.3: true end-of-queue / single-track completion — count the track that
                    // just finished before the stop clears isPlaying.
                    countPlayIfNaturalEndQualifies()
                    stopAtEndOfQueue()
                }
            }
        }

        // Nothing plays and nothing is on its way: this tick read the settled engine; it is the last.
        if !transportTickIsLive {
            transportTicker?.stop()
            transportTicker = nil
        }
    }

    /// The scrubber's playhead: at each tick, from the engine's latest sample (`transport`), and when
    /// the resume point moves (`nil`: no sample). While PAUSED (position-preserving Pause, D2) it shows
    /// where Play resumes — also while pausing, before the engine has stopped, so a scrub then isn't
    /// overwritten by the engine's last ticks (S10.8 G). While playing — or starting, from the place
    /// the start goes to (council C-15) — it follows the engine. Only a genuine stop (not playing, not
    /// paused) zeroes it. Writes only a change: Observation has no equality gate of its own.
    func placePlayhead(_ transport: TransportSnapshot?) {
        let position: Double = if let resumeAt = pausedResumePosition {
            resumeAt
        } else if playIntent {
            transport?.position ?? playbackPosition
        } else {
            0
        }
        if playbackPosition != position {
            playbackPosition = position
        }
    }

    /// Show an intent the signal path carries for the hero — Intensity, the crossfeed that plays — at
    /// once: the tick carries them while a song plays, but paused it sleeps.
    func refreshSignalPathIntents() {
        let fresh = withIntents(signalPath)
        if signalPath != fresh {
            signalPath = fresh
        }
    }

    /// `path` with the intents the hero reads from it (F4: the badge is a pure function of it).
    private func withIntents(_ path: SignalPathInfo) -> SignalPathInfo {
        var path = path
        path.intensityLinear = intensity
        path.crossfeedStrength = crossfeedPlays ? crossfeedStrength : nil
        path.carryPlayedPath(from: signalPath, plays: isPlaying && transportCommand == nil) // the DSP rows' path
        return path
    }

    /// Poll loudness + the signal path, SUPPRESSING same-value writes (break-it MINOR-3):
    /// Observation has no equality gate of its own, so unconditional assignment re-evaluated
    /// every signalPath/loudness observer (pill, hero badges, inspector, footer slot) 20×/s
    /// even while idle. These guards are what makes SignalPathInfo's "Equatable so redundant
    /// renders are suppressed" doc comment actually true.
    private func pollEngineReadouts(_ snapshot: EngineSnapshot) {
        let freshLoudness = snapshot.loudness
        if loudness != freshLoudness {
            loudness = freshLoudness
        }
        let freshPath = withIntents(snapshot.signalPath)
        if signalPath != freshPath {
            signalPath = freshPath
        }
        refreshEQDesignRate(snapshot.eqDesignRate)
    }
}
