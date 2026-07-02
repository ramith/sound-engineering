import AVFoundation
import Foundation

// MARK: - AudioViewModel spectrum timer

@MainActor
extension AudioViewModel {
    /// Start polling the spectrum double-buffer at 20 Hz.
    /// Safe to call multiple times — guards against duplicate timers.
    func startSpectrumTimer() {
        guard spectrumTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            // The timer is scheduled on RunLoop.main (below), so this callback always fires on
            // the main thread. assumeIsolated proves that to the compiler with no per-tick Task
            // allocation, letting us call the @MainActor tickSpectrum() directly.
            MainActor.assumeIsolated {
                self?.tickSpectrum()
            }
        }
        spectrumTimer = timer
        // Include in common run-loop modes so the timer fires during tracking
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopSpectrumTimer() {
        spectrumTimer?.invalidate()
        spectrumTimer = nil
    }

    /// Called at 20 Hz on the main thread. Reads the latest band magnitudes
    /// from the double-buffer, interpolates 44 bands → 88 display bars, and
    /// writes into `spectrumBars` to trigger SwiftUI observation.
    @MainActor
    func tickSpectrum() {
        // Poll the playhead + loudness + signal path every tick (independent of spectrum).
        playbackPosition = isPlaying ? (engine.currentPlaybackPosition() ?? playbackPosition) : 0
        loudness = engine.currentLoudness()
        var freshPath = engine.currentSignalPath()
        // F4: copy enhancement overlay fields so the badge is a pure function of the snapshot.
        freshPath.intensityLinear = intensity
        freshPath.crossfeedStrength = crossfeedEnabled ? crossfeedStrength : nil
        signalPath = freshPath

        // The output device disappeared (e.g. Bluetooth disconnected) and the engine paused —
        // reflect it in the UI and prompt the user to pick a device.
        if signalPath.interrupted, isPlaying {
            logUX("device-loss interrupt — stopping playback")
            isPlaying = false
            playbackPosition = 0
            errorMessage = "Output device disconnected — playback paused. Pick a device to resume."
            // Clear pending on-deck track; device loss invalidates the gapless queue.
            pendingNextIndex = nil
            Task { await engine.setNextTrack(nil) }
        }

        // --- Gapless auto-advance poll ---
        if isPlaying {
            let currentCount = engine.trackTransitionCount()
            if currentCount > lastTransitionCount {
                // A gapless seam completed: the on-deck track is now current.
                // Intentional: we advance by exactly ONE track per tick even if the count
                // jumped by more than one (e.g. two back-to-back very-short tracks in a
                // single 50 ms interval). The VM records the new baseline and calls
                // handleTrackTransition once; the next tick catches any remaining delta.
                // This keeps selectedTrackIndex in sync with pendingNextIndex at all times.
                lastTransitionCount = currentCount
                handleTrackTransition()
            } else if engine.playbackEnded() {
                // Current track ended with no GAPLESS continuation. If a track is still queued
                // (a Pure-path rate/format transition that couldn't be armed for a seamless seam),
                // advance to it with a fresh start — a brief, honest reconfigure gap. Otherwise the
                // queue is exhausted: stop. (Enhanced only reaches here with pendingNextIndex == nil,
                // since its resampler arms any rate, so this advance is the Pure rate-change path.)
                if let nextIdx = pendingNextIndex, nextIdx < playlist.count {
                    logUX("playbackEnded — advancing to queued track[\(nextIdx)] (reconfigure gap)")
                    selectedTrackIndex = nextIdx
                    // Clear the trigger SYNCHRONOUSLY before the async startPlayback: `playbackEnded()`
                    // stays true until startPlayback's Task runs `pureModeEngineStart` (≤ a few ticks
                    // on a DAC reconfigure), so without this the next 20 Hz tick would re-enter and
                    // launch a second `startAudio` that interrupts B mid-startup. startPlayback
                    // re-derives pendingNextIndex inside its Task, so nothing is lost.
                    pendingNextIndex = nil
                    startPlayback()
                } else {
                    logUX("playbackEnded — no next track, stopping")
                    isPlaying = false
                    playbackPosition = 0
                }
            }
        }

        guard engine.readSpectrumBands(into: &spectrumScratch) else { return }
        // Upsample 44 bands → 88 bars by linear interpolation between adjacent bands.
        // Bar i maps to fractional band position i / 2.0 (even bars fall on band centres).
        let bandCount = SpectrumConstants.bandCount
        let barCount = SpectrumConstants.displayBarCount
        for bar in 0 ..< barCount {
            let frac = Float(bar) / Float(barCount - 1) * Float(bandCount - 1)
            let lower = Int(frac)
            let upper = min(lower + 1, bandCount - 1)
            let weight = frac - Float(lower)
            spectrumBars[bar] = spectrumScratch[lower] * (1 - weight) + spectrumScratch[upper] * weight
        }
    }
}
