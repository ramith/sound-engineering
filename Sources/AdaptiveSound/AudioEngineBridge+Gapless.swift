import AVFoundation
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

    // MARK: - Seam handlers (called on resampleQueue)

    /// Gapless roll for the resampler sub-path.
    ///
    /// Called on `resampleQueue` after the current resampler session reaches EOF (its final buffer
    /// has been consumed by the player's buffer queue). Opens the next file, creates a NEW
    /// `AVAudioConverter` for it, and calls `startEnhancedResampler` WITHOUT stopping the player.
    /// Because the player's queue already contains A's audio tail and we are scheduling B's first
    /// buffers right behind it — with the player still running — the hardware clock is continuous
    /// and no silence is inserted.
    ///
    /// If the next track cannot be opened or the converter fails, falls back to `playFile` (which
    /// stops + restarts — a brief gap, but never silent).
    private func rollResamplerToNext(player: AVAudioPlayerNode) {
        guard let nextURL = onDeckURL else {
            gaplessPlaybackEnded = true
            enhancedPlayIntent = false // queue exhausted — don't auto-resume on a later config change
            logUX("gapless: resampler EOF — no next track, playback ended")
            return
        }
        onDeckURL = nil // consume the armed URL

        let didAccess = nextURL.startAccessingSecurityScopedResource()

        guard let nextFile = try? AVAudioFile(forReading: nextURL) else {
            if didAccess { nextURL.stopAccessingSecurityScopedResource() }
            logUX("gapless: resampler roll failed — cannot open '\(nextURL.lastPathComponent)'")
            // Degradation: fall back to a clean start on the global queue (stops + restarts,
            // brief gap). Sets playbackEnded if avEngine is gone (engine was shut down).
            DispatchQueue.global().async { [weak self] in
                guard let self, let engine = self.avEngine else {
                    self?.resampleQueue.async { self?.gaplessPlaybackEnded = true }
                    return
                }
                try? self.playFile(at: nextURL, engine: engine, playerNode: player)
            }
            return
        }
        // Security-scoped resource lifecycle: stop access after we open the file (AVAudioFile
        // retains its own file handle; we no longer need the security scope).
        if didAccess { nextURL.stopAccessingSecurityScopedResource() }

        let graphRate = player.outputFormat(forBus: 0).sampleRate
        let nextRate = nextFile.processingFormat.sampleRate

        if nextRate == graphRate {
            // Next file is 48 kHz — switch to the passthrough path for it.
            // stopEnhancedResampler bumps the generation so the old session's completions abandon;
            // we don't call player.stop() so the queue stays running.
            stopEnhancedResampler()
            bumpTransitionCount(player: player)
            lastFileURL = nextURL
            // Schedule the 48 kHz file directly; the player queue is still running.
            nextFile.framePosition = 0
            // swiftlint:disable:next line_length
            player.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak player] _ in
                guard let self, let livePlayer = player else { return }
                self.resampleQueue.async { self.onPassthroughEOF?(livePlayer) }
            }
            // Arm the passthrough hook so the track after this one can also be gapless.
            armPassthroughNextTrack(player: player)
            logUX("gapless: resampler→passthrough seam '\(nextURL.lastPathComponent)'")
            return
        }

        // Next file is also rate-mismatched: open a fresh converter and continue the resampler
        // chain. We are already on resampleQueue, so call primeEnhancedResamplerLocked directly
        // rather than startEnhancedResampler (which does resampleQueue.sync → deadlock C-1).
        lastFileURL = nextURL
        guard let converter = makeConverter(for: nextFile, player: player) else {
            // Converter creation failed: fall back to scheduleFile (brief gap, chain preserved).
            // S-1: add .dataPlayedBack completion so onPassthroughEOF fires and the chain continues.
            bumpTransitionCount(player: player)
            armPassthroughNextTrack(player: player)
            // swiftlint:disable:next line_length
            player.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak player] _ in
                guard let self, let livePlayer = player else { return }
                self.resampleQueue.async { self.onPassthroughEOF?(livePlayer) }
            }
            logUX("gapless: resampler→passthrough fallback seam "
                + "'\(nextURL.lastPathComponent)' (converter failed)")
            return
        }
        let nextSession = EnhancedResampleSession(
            converter: converter,
            audioFile: nextFile,
            inputFormat: nextFile.processingFormat,
            outputFormat: player.outputFormat(forBus: 0),
            inputChunkFrames: AudioEngineBridge.resampleInputChunkFrames
        )
        let primed = primeEnhancedResamplerLocked(
            session: nextSession, audioFile: nextFile, player: player, startFrame: 0
        )
        if primed > 0 {
            bumpTransitionCount(player: player)
            armResamplerNextTrack(player: player)
            logUX("gapless: resampler→resampler seam '\(nextURL.lastPathComponent)' "
                + "(\(Int(nextRate))→\(Int(graphRate)))")
        } else {
            // primeEnhancedResamplerLocked scheduled nothing (empty file). Fall back to scheduleFile.
            // P1-2: clear resampleSession so a later seek/reestablish takes the passthrough branch
            // rather than the (now-stale) resampler branch. primeEnhancedResamplerLocked sets it
            // non-nil at the top of its prime even when 0 buffers are produced.
            resampleSession = nil
            // S-1: completion preserves the chain.
            bumpTransitionCount(player: player)
            armPassthroughNextTrack(player: player)
            // swiftlint:disable:next line_length
            player.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak player] _ in
                guard let self, let livePlayer = player else { return }
                self.resampleQueue.async { self.onPassthroughEOF?(livePlayer) }
            }
            logUX("gapless: resampler→passthrough fallback seam "
                + "'\(nextURL.lastPathComponent)' (empty prime, scheduleFile)")
        }
    }

    /// Gapless roll for the 48 kHz passthrough sub-path.
    ///
    /// Called on `resampleQueue` after the current `scheduleFile` session's `.dataPlayedBack`
    /// callback fires (the hardware has played the last sample of the current track). Opens the
    /// next file and either chains another `scheduleFile` (48 kHz next) or starts the resampler
    /// (rate-mismatched next) — in both cases WITHOUT calling `player.stop()`.
    private func rollPassthroughToNext(player: AVAudioPlayerNode) {
        guard let nextURL = onDeckURL else {
            gaplessPlaybackEnded = true
            enhancedPlayIntent = false // queue exhausted — don't auto-resume on a later config change
            logUX("gapless: passthrough EOF — no next track, playback ended")
            return
        }
        onDeckURL = nil // consume the armed URL

        let didAccess = nextURL.startAccessingSecurityScopedResource()

        guard let nextFile = try? AVAudioFile(forReading: nextURL) else {
            if didAccess { nextURL.stopAccessingSecurityScopedResource() }
            logUX("gapless: passthrough roll failed — cannot open '\(nextURL.lastPathComponent)'")
            DispatchQueue.global().async { [weak self] in
                guard let self, let engine = self.avEngine else {
                    self?.resampleQueue.async { self?.gaplessPlaybackEnded = true }
                    return
                }
                try? self.playFile(at: nextURL, engine: engine, playerNode: player)
            }
            return
        }
        if didAccess { nextURL.stopAccessingSecurityScopedResource() }

        let graphRate = player.outputFormat(forBus: 0).sampleRate
        let nextRate = nextFile.processingFormat.sampleRate
        lastFileURL = nextURL

        if nextRate == graphRate {
            // Both current and next are 48 kHz: consecutive scheduleFile calls play back-to-back,
            // byte-exact. This is the spec's "consecutive scheduleFile" gapless path.
            bumpTransitionCount(player: player)
            nextFile.framePosition = 0
            // swiftlint:disable:next line_length
            player.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak player] _ in
                guard let self, let livePlayer = player else { return }
                self.resampleQueue.async { self.onPassthroughEOF?(livePlayer) }
            }
            armPassthroughNextTrack(player: player)
            logUX("gapless: passthrough→passthrough seam '\(nextURL.lastPathComponent)'")
        } else {
            // Next track is rate-mismatched: start the resampler sub-path for it. The player is
            // still running (no stop), so the primed buffers join the queue behind the last bytes
            // of the passthrough track. We are already on resampleQueue, so call
            // primeEnhancedResamplerLocked directly — calling startEnhancedResampler would
            // resampleQueue.sync onto ourselves (C-1 deadlock).
            guard let converter = makeConverter(for: nextFile, player: player) else {
                // Converter failed: fall back to scheduleFile. S-1: add completion for chain.
                bumpTransitionCount(player: player)
                armPassthroughNextTrack(player: player)
                // swiftlint:disable:next line_length
                player.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak player] _ in
                    guard let self, let livePlayer = player else { return }
                    self.resampleQueue.async { self.onPassthroughEOF?(livePlayer) }
                }
                logUX("gapless: passthrough→passthrough fallback seam "
                    + "'\(nextURL.lastPathComponent)' (converter failed)")
                return
            }
            let nextSession = EnhancedResampleSession(
                converter: converter,
                audioFile: nextFile,
                inputFormat: nextFile.processingFormat,
                outputFormat: player.outputFormat(forBus: 0),
                inputChunkFrames: AudioEngineBridge.resampleInputChunkFrames
            )
            let primed = primeEnhancedResamplerLocked(
                session: nextSession, audioFile: nextFile, player: player, startFrame: 0
            )
            bumpTransitionCount(player: player)
            if primed > 0 {
                armResamplerNextTrack(player: player)
                logUX("gapless: passthrough→resampler seam '\(nextURL.lastPathComponent)' "
                    + "(\(Int(nextRate))→\(Int(graphRate)))")
            } else {
                // primeEnhancedResamplerLocked scheduled nothing (empty file). S-1: completion.
                // P1-2: clear resampleSession so a later seek/reestablish takes the passthrough
                // branch rather than the stale resampler branch (mirrors the
                // startEnhancedResampler guard for the primed == 0 case).
                resampleSession = nil
                armPassthroughNextTrack(player: player)
                // swiftlint:disable:next line_length
                player.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak player] _ in
                    guard let self, let livePlayer = player else { return }
                    self.resampleQueue.async { self.onPassthroughEOF?(livePlayer) }
                }
                logUX("gapless: passthrough→passthrough fallback seam "
                    + "'\(nextURL.lastPathComponent)' (empty prime, scheduleFile)")
            }
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
    private func bumpTransitionCount(player: AVAudioPlayerNode) {
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
        enhancedPositionBaseSeconds = baseSeconds
        lastKnownEnhancedPositionSeconds = 0
        logUX("gapless: seam #\(gaplessTransitionCount) — position reset")
    }

    // MARK: - Converter factory (shared by seam handlers)

    /// Create a `.max`-quality `AVAudioConverter` from `file`'s processing format to the player's
    /// output format. Returns `nil` if the converter cannot be created (caller must fall back to
    /// `scheduleFile`). MUST be called on `resampleQueue`.
    private func makeConverter(
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
