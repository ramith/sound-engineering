@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge Enhanced-path gapless engine

/// Gapless on the Enhanced path (the engine graph + streaming resampler): `setNextTrack`, and the
/// seam count and end-of-queue flag the transport clock publishes in `TransportSnapshot`.
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
/// The gapless seam state (`onDeckURL`, `onResamplerEOF`, `onPassthroughEOF`) is read and
/// written only on `resampleQueue`, the serial queue that owns the resampler/converter state;
/// `setNextTrack` hops there with `async`. The seam count and end flag
/// (`gaplessTransitionCount`, `gaplessPlaybackEnded`) are written there too, but they are named
/// acquire/release atomics: the transport clock reads them on `engineQueue` and publishes them in
/// the `TransportSnapshot` copy. The main thread never reads them, nor syncs onto
/// `resampleQueue` (S10.8 G).
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
        if activePathKind == .pure {
            await setPureNextTrack(fileURL)
            return
        }

        guard activePathKind == .enhanced else { return }
        // Prefetch the armed track's loudness profile for its seam (the engine switches to it
        // only when it becomes AUDIBLE, at bumpTransitionCount — never here).
        prefetchTrackLoudness(fileURL)
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

    /// Pure-path on-deck arm (S3 F3): open the next source on a global queue (the network-slow step,
    /// kept off every bridge queue), then arm the pre-opened decoder — or clear the deck — on
    /// `engineQueue`, where every Pure C-ABI call is serialized with the clock, seek and teardown
    /// (`withPureEngine`). Split out of setNextTrack so each transport path stays within the
    /// cyclomatic budget. result: 2 armed / 1 reconfigure / 0 error.
    private func setPureNextTrack(_ fileURL: URL?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard let url = fileURL else {
                engineQueue.async {
                    _ = self.withPureEngine { pureModeEngineClearNextTrack($0) }
                    continuation.resume()
                }
                return
            }
            DispatchQueue.global().async {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard let decoder = url.path.withCString({ pureModeOpenDecodeSource($0) }) else {
                    logUX("pure setNextTrack '\(url.lastPathComponent)' → error (open failed)")
                    continuation.resume()
                    return
                }
                // Hand the opened decoder to engineQueue by its address (a C handle; the ownership
                // moves with it): no worker blocks while a transport change finishes there.
                let decoderAddress = UInt(bitPattern: decoder)
                self.engineQueue.async {
                    guard let decoder = UnsafeMutableRawPointer(bitPattern: decoderAddress) else {
                        continuation.resume()
                        return
                    }
                    // arm TAKES OWNERSHIP; nil (no longer Pure) ⇒ arm never ran ⇒ free the decoder.
                    if let result = self.withPureEngine({ pureModeEngineArmOpenedNextTrack($0, decoder) }) {
                        logUX("pure setNextTrack '\(url.lastPathComponent)' → \(Self.pureArmLabel(result))")
                    } else {
                        pureModeDestroyDecodeSource(decoder)
                    }
                    continuation.resume()
                }
            }
        }
    }

    /// Label for a `pureModeEngineArmOpenedNextTrack` result (2 armed / 1 reconfigure / 0 error).
    private static func pureArmLabel(_ result: Int32) -> String {
        switch result {
        case 2: return "armed (gapless)"
        case 1: return "needs-reconfigure (gap on advance)"
        default: return "error"
        }
    }

    // The seam count and the end flag reach the view model through the transport snapshot
    // (`snapshot()`'s transport, AudioEngineBridge+TransportClock), sampled off the main thread.

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

    /// Bump `gaplessTransitionCount` and reset the position base to re-zero the new track, and
    /// tell the engine `nextURL` is the audible track now (its loudness-neutral EQ gain).
    ///
    /// Called at every real seam (never on seek or stop). Captures the player's current
    /// `sampleTime` to set `enhancedPositionBaseSeconds` so `liveEnhancedPosition()` reports
    /// 0.0 for the first sample of the new track and grows from there.
    ///
    /// N-2 fix: when `playerTime(forNodeTime:)` returns nil (engine reconfiguring at the seam),
    /// use `-lastKnownEnhancedPositionSeconds` as the base. This counteracts the accumulated
    /// sampleTime so `liveEnhancedPosition()` reads ~0 for the new track instead of jumping
    /// to track-A-duration and counting forward from there.
    ///
    /// MUST be called on `resampleQueue` (all gapless state lives there).
    func bumpTransitionCount(player: AVAudioPlayerNode, nextURL: URL) {
        gaplessTransitionCounter.wrappingAdd(1, ordering: .acquiringAndReleasing)
        trackBecameAudible(nextURL, gaplessSeam: true)

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
