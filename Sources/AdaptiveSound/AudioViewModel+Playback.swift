import AVFoundation
import Foundation

// MARK: - AudioViewModel playback control (start / prime / seek)

/// Playback bring-up and seeking, split out of the main `AudioViewModel` body (F: keep
/// AudioViewModel.swift — which must hold all `@Observable` stored properties, since extensions
/// cannot — under the file-length budget). Transport buttons (play/pause/next/previous) live in
/// AudioViewModel+Transport.swift; auto-advance in AudioViewModel+AutoAdvance.swift.
@MainActor
extension AudioViewModel {
    // MARK: - Playback Control

    /// Start playback of the selected track. When `resumeFrom` is non-nil (a position-preserving
    /// Pause resume, D2) the engine seeks to that offset immediately after starting, so playback
    /// continues from where it was paused rather than the top. All other callers pass nil (start
    /// from 0).
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
            + "pureMode=\(pureModeEnabled) device='\(selectedDevice?.name ?? "none")'"
            + (resumeFrom.map { " resumeFrom=\(secs($0))s" } ?? ""))

        refreshDuration(for: fileURL)

        // A fresh start (not a pause/resume seek) begins a NEW ≥60% play-through (S10.6). Reset
        // SYNCHRONOUSLY here, BEFORE the async Task below: on a manual switch `selectedTrackIndex`
        // is already the new track, and the 20 Hz tick fires while the Task is parked at
        // `await engine.startAudio`. If the reset were deferred into the Task, those ticks would
        // keep accruing the OUTGOING track's `heardSeconds` and could cross the threshold — counting
        // the play against the newly-selected track (QA break-it #1). A pause-resume (resumeFrom !=
        // nil) continues the same play-through — no reset.
        if resumeFrom == nil { resetPlayTracking() }

        // Snapshot index and mode for use inside the Task (avoids capturing `self` for
        // values that could change between now and when the Task body runs).
        let startIndex = selectedTrackIndex
        let pureModeSnapshot = pureModeEnabled

        Task {
            do {
                try await engine.startAudio(fileURL: fileURL, pureMode: pureModeSnapshot)
                // Position-preserving Pause resume: seek to the saved offset after the engine has
                // started on the (possibly reconfigured) device.
                if let resumeFrom, resumeFrom > 0 {
                    await engine.seek(to: resumeFrom)
                }
                await primeGaplessPipeline(startIndex: startIndex, pureMode: pureModeSnapshot)
                isPlaying = true
                errorMessage = nil
            } catch {
                errorMessage = "Playback failed: \(error.localizedDescription)"
                isPlaying = false
                pendingNextIndex = nil
            }
        }
    }

    /// Compute the current file's duration off-main from `AVAudioFile` (more reliable than the
    /// metadata scan's `durationSeconds` for M4A, which can read 0) and publish it on the main
    /// actor. Fire-and-forget. Shared by `startPlayback` and the gapless auto-advance seam
    /// (S3 LOW-a — was duplicated); `logLabel` distinguishes the call site in the UX log.
    func refreshDuration(for fileURL: URL, logLabel: String = "duration") {
        Task.detached(priority: .userInitiated) { [weak self] in
            let computedDuration: Double = {
                guard let file = try? AVAudioFile(forReading: fileURL) else { return 0 }
                let rate = file.processingFormat.sampleRate
                return rate > 0 ? Double(file.length) / rate : 0
            }()
            await MainActor.run { [computedDuration] in
                self?.duration = computedDuration
                logUX("\(logLabel) = \(secs(computedDuration))s")
            }
        }
    }

    /// Prime the gapless pipeline after `startAudio` succeeds: reset the transition-counter
    /// baseline and arm the on-deck track so the engine can pre-schedule it. Runs on the main
    /// actor (the VM's isolation); the `engine.setNextTrack`/`trackTransitionCount` calls hop to
    /// the engine's own queues internally. Behaviour is identical to the previously-inlined block.
    private func primeGaplessPipeline(startIndex: Int?, pureMode: Bool) async {
        lastTransitionCount = engine.trackTransitionCount()

        let currentIdx = startIndex ?? selectedTrackIndex
        let nextIdx = computeNextIndex(current: currentIdx ?? 0, playlistCount: playlist.count)
        pendingNextIndex = nextIdx

        if let idx = nextIdx, idx < playlist.count {
            let nextURL = playlist[idx].absoluteURL
            await engine.setNextTrack(nextURL)
            logUX("startPlayback: primed next index=\(idx) pureMode=\(pureMode)")
        } else {
            await engine.setNextTrack(nil)
            logUX("startPlayback: no next track to prime (single-track or end of playlist)")
        }
    }

    /// Seek to `seconds` from the start of the current file.
    /// Updates `playbackPosition` immediately to avoid UI jitter while the engine seeks.
    func seek(to seconds: Double) {
        logUX("seek → \(secs(seconds))s "
            + "(from \(secs(playbackPosition))s, dur \(secs(duration))s, "
            + "path=\(signalPath.path == .pure ? "Pure" : "Enhanced"))")
        playbackPosition = seconds
        Task {
            await engine.seek(to: seconds)
        }
    }
}
