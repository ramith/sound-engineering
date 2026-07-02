@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge Enhanced-path gapless engine

/// Implements the three gapless protocol requirements (`setNextTrack`, `trackTransitionCount`,
/// `playbackEnded`) for the Enhanced path (AVAudioEngine + streaming resampler).
///
/// ## Architecture overview
///
/// Two sub-paths exist on the Enhanced path, and gapless is handled differently for each:
///
/// **Resampler sub-path** (file rate ≠ 48 kHz, driven by `AudioEngineBridge+EnhancedResampler`):
///   The `onResamplerEOF` hook is installed on `resampleQueue` after `startEnhancedResampler`
///   succeeds. When the resampler's completion chain reaches end-of-file it fires the hook (still
///   on `resampleQueue`). If a next track is armed, `rollResamplerToNext` opens the new file,
///   builds a NEW `AVAudioConverter`, and calls `startEnhancedResampler` without stopping the
///   player — the buffer queue stays contiguous → gap-free.
///
/// **Passthrough sub-path** (48 kHz file, `scheduleFile`):
///   `playFile` schedules the file with `completionCallbackType: .dataPlayedBack` and dispatches
///   onto `resampleQueue` when the hardware finishes playing the last sample. `onPassthroughEOF`
///   fires there. If a next track is armed and it is also 48 kHz → `scheduleFile` the new file
///   immediately (consecutive schedules play back-to-back, byte-exact); if the next track is a
///   different rate → `startEnhancedResampler` for it without stopping the player.
///
/// ## Thread model
///
/// All gapless state (`onDeckURL`, `gaplessTransitionCount`, `gaplessPlaybackEnded`,
/// `onResamplerEOF`, `onPassthroughEOF`) is read and written exclusively on `resampleQueue`
/// (the same serial queue that owns all resampler/converter state). The protocol methods
/// `setNextTrack`, `trackTransitionCount`, and `playbackEnded` marshal onto `resampleQueue`
/// via `async` or `sync` to honour this invariant. The VM polls the counter/flag at 20 Hz from
/// `DispatchQueue.main`; `resampleQueue.sync` in the read path is instantaneous (the queue is
/// never held under a slow operation when a protocol read arrives).
///
/// ## Gapless AAC/MP3 note
///
/// `AVAudioFile` / `ExtAudioFile` automatically trims AAC priming silence and MP3 LAME delay/
/// padding (via the file's edit list and `kExtAudioFileProperty_ClientDataFormat`). This is
/// Apple's responsibility on the Enhanced path; we must not disable or override it. The explicit
/// FFmpeg-path trim (for the Pure path) is Stage 2.
extension AudioEngineBridge {
    // MARK: - Protocol requirements (AudioPlaybackEngine)

    /// Supply (or clear, with `nil`) the track to play gaplessly after the current one finishes.
    ///
    /// - If called while an Enhanced session is active, arms the appropriate EOF hook.
    /// - If called with `nil`, clears the on-deck slot and disarms any armed hook.
    /// - A seek must NOT consume the on-deck track; user stop clears it (done in `stopAudio`).
    /// - Safe to call from any thread; all state is marshalled onto `resampleQueue`.
    func setNextTrack(_ fileURL: URL?) async {
        // Pure path: route to the HAL GaplessSource C-ABI. A same-format next track arms a
        // sample-accurate seam (result 2); a rate/format mismatch (result 1) is NOT armed — the
        // track still plays, but via a fresh start (the brief reconfigure gap) when the VM sees
        // playbackEnded with a track still queued. result 0 = error (unreadable/unsupported).
        if activePath == .pure {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    guard let engine = self.pureEngine else { continuation.resume(); return }
                    if let url = fileURL {
                        let didAccess = url.startAccessingSecurityScopedResource()
                        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                        let result = url.path.withCString { pureModeEngineSetNextTrack(engine, $0) }
                        logUX("pure setNextTrack '\(url.lastPathComponent)' → "
                            + (result == 2 ? "armed (gapless)"
                                : result == 1 ? "needs-reconfigure (gap on advance)" : "error"))
                    } else {
                        pureModeEngineClearNextTrack(engine)
                    }
                    continuation.resume()
                }
            }
            return
        }

        guard activePath == .enhanced else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            resampleQueue.async {
                self.onDeckURL = fileURL
                if fileURL == nil {
                    // Disarm: clear both EOF hooks so no stale handler fires.
                    self.onResamplerEOF = nil
                    self.onPassthroughEOF = nil
                    continuation.resume()
                    return
                }
                // Arm the correct hook based on which sub-path is currently active.
                if let player = self.playerNode {
                    if self.resampleSession != nil {
                        self.armResamplerNextTrack(player: player)
                    } else {
                        self.armPassthroughNextTrack(player: player)
                    }
                }
                continuation.resume()
            }
        }
    }

    /// Monotonic count of completed gapless seams. The view model polls this at 20 Hz;
    /// an increase signals that `onDeckURL` became the current track.
    func trackTransitionCount() -> UInt64 {
        // Pure path: the HAL GaplessSource owns the seam counter (polling it also reaps a retired
        // source off-RT — that's why the VM polls every tick). Enhanced path: the resampler counter.
        if activePath == .pure, let engine = pureEngine {
            return pureModeEnginePollTrackAdvance(engine)
        }
        return resampleQueue.sync { gaplessTransitionCount }
    }

    /// `true` once the current track ended with no next track on deck (queue exhausted).
    /// Cleared on the next `startAudio`.
    func playbackEnded() -> Bool {
        if activePath == .pure, let engine = pureEngine {
            return pureModeEnginePlaybackEnded(engine) == 1
        }
        return resampleQueue.sync { gaplessPlaybackEnded }
    }

    // MARK: - Arm helpers (called on resampleQueue)

    /// Install the `onResamplerEOF` hook for the currently active resampler session.
    /// MUST be called on `resampleQueue`. No-op if no session is active.
    func armResamplerNextTrack(player: AVAudioPlayerNode) {
        onResamplerEOF = { [weak self, weak player] _, _ in
            guard let self, let player else { return }
            self.onResamplerEOF = nil // consume the one-shot hook
            self.rollResamplerToNext(player: player)
        }
    }

    /// Install the `onPassthroughEOF` hook for the current 48 kHz passthrough session.
    /// MUST be called on `resampleQueue`. No-op if the player node is not reachable.
    func armPassthroughNextTrack(player: AVAudioPlayerNode) {
        onPassthroughEOF = { [weak self, weak player] _ in
            guard let self, let livePlayer = player else { return }
            self.onPassthroughEOF = nil // consume the one-shot hook
            self.rollPassthroughToNext(player: livePlayer)
        }
    }

    // MARK: - Position continuity at seams

    /// Bump `gaplessTransitionCount` and reset the position base to re-zero the new track.
    ///
    /// Called at every real seam (never on seek or stop). Captures the player's current
    /// `sampleTime` to set `enhancedPositionBaseSeconds` so `currentPlaybackPosition()` reports
    /// 0.0 for the first sample of the new track and grows from there.
    ///
    /// N-2 fix: when `playerTime(forNodeTime:)` returns nil (engine reconfiguring at the seam),
    /// use `-lastKnownEnhancedPositionSeconds` as the base. This counteracts the accumulated
    /// sampleTime so `currentPlaybackPosition()` reads ~0 for the new track instead of jumping
    /// to track-A-duration and counting forward from there.
    ///
    /// MUST be called on `resampleQueue` (all gapless state lives there).
    func bumpTransitionCount(player: AVAudioPlayerNode) {
        gaplessTransitionCount &+= 1

        // Capture the player's sampleTime off the audio thread (safe — CoreAudio property read).
        // The player is still running at the seam, so sampleTime is the hardware clock position at
        // the boundary. base = -(sampleTime/rate) → position = base + sampleTime/rate = 0 at seam.
        let nodeTime = player.lastRenderTime
        let pTime = nodeTime.flatMap { player.playerTime(forNodeTime: $0) }
        let baseSeconds: Double
        if let pTime, pTime.sampleRate > 0 {
            baseSeconds = -Double(pTime.sampleTime) / pTime.sampleRate
        } else {
            // N-2: render time unavailable (engine mid-reconfiguration). Use the negative of the
            // last known position so that base + sampleTime/rate ≈ 0 for the new track, rather
            // than jumping forward by the full accumulated sampleTime.
            baseSeconds = -lastKnownEnhancedPositionSeconds
        }
        setEnhancedPositionBaseSeconds(baseSeconds)
        setLastKnownEnhancedPositionSeconds(0)
        logUX("gapless: seam #\(gaplessTransitionCount) — position reset")
    }

    // MARK: - Converter factory (shared by seam handlers)

    /// Create a `.max`-quality `AVAudioConverter` from `file`'s processing format to the player's
    /// output format. Returns `nil` if the converter cannot be created (caller must fall back to
    /// `scheduleFile`). MUST be called on `resampleQueue`.
    func makeConverter(
        for audioFile: AVAudioFile,
        player: AVAudioPlayerNode
    ) -> AVAudioConverter? {
        let inputFormat = audioFile.processingFormat
        let outputFormat = player.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            NSLog("[AudioEngineBridge] AVAudioConverter creation failed "
                + "(\(inputFormat.sampleRate) -> \(outputFormat.sampleRate))")
            return nil
        }
        converter.sampleRateConverterQuality = .max
        return converter
    }
}

// The seam handlers (rollResamplerToNext / rollPassthroughToNext) and their shared
// sub-steps live in AudioEngineBridge+GaplessRoll.swift.
