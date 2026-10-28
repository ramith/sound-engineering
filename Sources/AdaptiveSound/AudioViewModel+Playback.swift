import AVFoundation
import Foundation
import LevelingKit
import PlaybackQueueKit

// MARK: - AudioViewModel playback control (start / prime / seek)

/// Playback bring-up and seeking, split out of the main `AudioViewModel` body (F: keep
/// AudioViewModel.swift — which must hold all `@Observable` stored properties, since extensions
/// cannot — under the file-length budget). Transport buttons (play/pause/next/previous) live in
/// AudioViewModel+Transport.swift; auto-advance in AudioViewModel+AutoAdvance.swift.
@MainActor
extension AudioViewModel {
    // MARK: - Playback Control

    /// Start playback of the selected track. When `resumeFrom` is non-nil (a position-preserving
    /// Pause resume, D2; a move to another device) the engine STARTS at that offset — never from 0
    /// then a seek, which on Pure was audible. All other callers pass nil (start from 0).
    func startPlayback(resumeFrom: Double? = nil) {
        guard isEngineReady else {
            errorMessage = "Engine not ready"
            return
        }

        guard let selectedIndex = selectedTrackIndex, selectedIndex < playlist.count else {
            errorMessage = "No track selected"
            return
        }

        let startFile = playlist[selectedIndex]
        let fileURL = startFile.absoluteURL
        // Show the resume point immediately (avoid a scrubber flash to 0 before the seek lands).
        playbackPosition = resumeFrom ?? 0
        logUX("play: track[\(selectedIndex)] '\(playlist[selectedIndex].name)' "
            + "pureMode=\(pureStartNote) device='\(selectedDevice?.name ?? "none")'"
            + (resumeFrom.map { " resumeFrom=\(secs($0))s" } ?? ""))

        refreshDuration(for: fileURL)

        // A fresh start (not a pause/resume seek) begins a NEW ≥60% play-through (S10.6). Reset
        // SYNCHRONOUSLY here, BEFORE the async Task below: on a manual switch `selectedTrackIndex`
        // is already the new track, and the 20 Hz tick fires while the Task is parked at
        // `await engine.startAudio`. If the reset were deferred into the Task, those ticks would
        // keep accruing the OUTGOING track's `heardSeconds` and could cross the threshold — counting
        // the play against the newly-selected track (QA break-it #1). A pause-resume (resumeFrom !=
        // nil) continues the same play-through — no reset.
        if resumeFrom == nil {
            resetPlayTracking()
        }

        // Snapshot the start's SLOT and the mode for use inside the Task. The slot, not its row: a
        // queue edit while the start runs (the launch restore joining, a removal above it) moves rows,
        // and the prime must arm what plays after THIS song, wherever it sits by then.
        let startSlot = selectedSlotID
        let pureModeSnapshot = pureModeEnabled // the engine decides how Master Gain plays on Pure
        // Numbered now, synchronously: until the engine begins this start, the ticks ignore the
        // samples of the playback it replaces (the old track's playhead and end flag). It owns the
        // transport and its on-deck requests from now on (the engine drops any made for the playback
        // it replaces), until a newer start or a stop is asked (council C-15).
        let epoch = nextStartEpoch()

        work.spawn { [self] in
            do {
                // The leveling decision travels with the start (R1.1-B, §S3). Off until lane 3's decisions
                // land (W5): no leveling gain; the fold's trim and the peak cap still apply.
                try await engine.startAudio(fileURL: fileURL, pureMode: pureModeSnapshot,
                                            startAt: resumeFrom ?? 0, epoch: epoch, leveling: .off)
                // A stop, a pause or a newer start asked while this one ran owns the transport now
                // (the engine dropped this start if it had begun that one first): neither prime the
                // queue with a pick for a replaced playback nor mark playing over what was asked since.
                guard transportCommand == .start(epoch) else { return }
                transportCommand = .prime(epoch)
                await primeGaplessPipeline(startSlot: startSlot, pureMode: pureModeSnapshot)
                guard finish(.prime(epoch)) else { return }
                isPlaying = true
                errorMessage = nil
            } catch {
                // A newer start or stop owns the transport: what plays now is its outcome, not this one.
                if finish(.start(epoch)) {
                    errorMessage = "Playback failed: \(error.localizedDescription)"
                    isPlaying = false
                    pendingNextIndex = nil
                }
                // Self-heal (break-it): engine-not-ready is recoverable — rebuild the graph
                // so the NEXT play press succeeds. `retryInitialization` is internally
                // guarded against re-entry while an init is already in flight.
                if case AudioBridgeError.engineNotInitialized = error {
                    logUX("startPlayback: engine not initialized — self-healing via retryInitialization")
                    retryInitialization()
                }
            }
        }
    }

    /// Compute the current file's duration off-main from `AVAudioFile` (more reliable than the
    /// metadata scan's `durationSeconds` for M4A, which can read 0) and publish it on the main
    /// actor. Fire-and-forget. Shared by `startPlayback` and the gapless auto-advance seam
    /// (S3 LOW-a — was duplicated); `logLabel` distinguishes the call site in the UX log.
    func refreshDuration(for fileURL: URL, logLabel: String = "duration") {
        work.spawnDetached(priority: .userInitiated) { [weak self] in
            let computedDuration: Double = {
                guard let file = try? AVAudioFile(forReading: fileURL) else { return 0 }
                let rate = file.processingFormat.sampleRate
                return rate > 0 ? Double(file.length) / rate : 0
            }()
            await MainActor.run { [computedDuration] in
                self?.duration = computedDuration
                logUX("\(logLabel) = \(secs(computedDuration))s")
                // The real (async) duration landed — re-push Now Playing so Control Center's
                // scrubber shows the true length (closes the M4A 0-length flash, S10.4 D4).
                self?.onNowPlayingRefresh?()
            }
        }
    }

    /// Prime the gapless pipeline after `startAudio` succeeds: reset the transition-counter
    /// baseline and arm the on-deck track so the engine can pre-schedule it. Runs on the main
    /// actor (the VM's isolation): the baseline comes from the snapshot copy, and the request
    /// (`armOnDeck`) hops to the engine's own queues; it returns once the engine settled it.
    private func primeGaplessPipeline(startSlot: UUID?, pureMode: Bool) async {
        lastTransitionCount = engine.snapshot().transport.transitionCount // fresh: startAudio sampled it

        let currentIdx = startSlot.flatMap(queueRow(of:)) ?? selectedTrackIndex
        let nextIdx = computeNextIndex(current: currentIdx ?? 0, playlistCount: playlist.count)
        if let idx = nextIdx {
            logUX("startPlayback: priming next index=\(idx) pureMode=\(pureMode)")
        } else {
            logUX("startPlayback: no next track to prime (single-track or end of playlist)")
        }
        await armOnDeck(index: nextIdx).value
    }

    /// Seek to `seconds` from the start of the current file (`SeekRoute`, S10.8 G). Playing: the
    /// engine seeks. Paused: only the resume point moves, and Play resumes there — the engine is
    /// stopped, and a segment scheduled onto it would play ahead of the next song. Stopped: nothing
    /// is loaded, so nothing moves. Updates `playbackPosition` immediately to avoid UI jitter, and keeps the
    /// place at once, playing or paused: a crash comes back where the listener scrubbed to (+QueueMirror).
    ///
    /// A start or a stop on its way (council C-15) is not "playing" here: a seek numbered after it was
    /// meant for the playback it replaces, and could overtake it and drop it at the engine. A pause on
    /// its way has its resume point already, so a scrub then moves that.
    ///
    /// The request is placed first by the one rule (`SeekTarget.place`, C-25): not a number → no seek
    /// at all; otherwise inside 0…duration. The end itself is a place: the engine ends the track
    /// there, and the tick advances as at any end.
    func seek(to requested: Double) {
        guard let seconds = SeekTarget.place(requested, duration: duration) else {
            logUX("seek → \(requested) refused (not a place)")
            return
        }
        let route = SeekRoute.route(isPlaying: isPlaying && transportCommand == nil,
                                    isPaused: pausedResumePosition != nil)
        logUX("seek → \(secs(seconds))s "
            + "(from \(secs(playbackPosition))s, dur \(secs(duration))s, "
            + "path=\(signalPath.path == .pure ? "Pure" : "Enhanced"), route=\(route))")
        switch route {
        case .engine:
            let epoch = nextTransportEpoch() // the old playhead is ignored until the seek lands
            work.spawn { [self] in
                do {
                    try await engine.seek(to: seconds, epoch: epoch)
                } catch {
                    // A seek that did not move: say so; the next tick shows where it plays.
                    logUX("seek → \(secs(seconds))s failed: \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                }
            }
        case .resumePoint:
            resumePoint?.move(to: seconds)
        case .ignore:
            return
        }
        playbackPosition = seconds
        // A place the listener chose: written at once, not at the cadence the song's own progress keeps (founder,
        // 2026-10-28). Paused, the resume point's move asked too; asks in one turn are one write.
        queuePlayheadMoved(cadenced: false)
        onNowPlayingRefresh?() // re-anchor the Control Center scrubber to the new position (S10.4)
    }
}
