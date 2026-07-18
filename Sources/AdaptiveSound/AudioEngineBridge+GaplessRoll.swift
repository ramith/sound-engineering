@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge Enhanced-path gapless seam handlers

/// The two seam handlers (`rollResamplerToNext` / `rollPassthroughToNext`) and their shared
/// sub-steps, split out of `AudioEngineBridge+Gapless.swift` to keep that file under the
/// file-length limit and to keep each handler under the body-length / cyclomatic-complexity
/// limits.
///
/// ## Thread model (unchanged)
///
/// Everything here runs on `resampleQueue` (the serial queue that owns all resampler/converter
/// state and all gapless seam state — `onDeckURL`, `gaplessTransitionCount`,
/// `gaplessPlaybackEnded`, the EOF hooks). The handlers are invoked from the EOF hooks installed
/// by `armResamplerNextTrack` / `armPassthroughNextTrack`, both of which dispatch onto
/// `resampleQueue`. The `primeEnhancedResamplerLocked` deadlock-guard is preserved: it is called
/// DIRECTLY here (never via `startEnhancedResampler`, which would `resampleQueue.sync` onto
/// ourselves → C-1 deadlock).
extension AudioEngineBridge {
    // MARK: - Seam handlers (called on resampleQueue)

    /// Gapless roll for the resampler sub-path.
    ///
    /// Called on `resampleQueue` after the current resampler session reaches EOF (its final buffer
    /// has been consumed by the player's buffer queue). Opens the next file, creates a NEW
    /// `AVAudioConverter` for it, and continues the resampler chain WITHOUT stopping the player.
    /// Because the player's queue already contains A's audio tail and we are scheduling B's first
    /// buffers right behind it — with the player still running — the hardware clock is continuous
    /// and no silence is inserted.
    ///
    /// If the next track cannot be opened or the converter fails, falls back to `playFile` (which
    /// stops + restarts — a brief gap, but never silent).
    func rollResamplerToNext(player: AVAudioPlayerNode) {
        guard let nextURL = consumeOnDeckURL(context: "resampler") else { return }

        guard let nextFile = openNextFileOrRestart(nextURL, player: player) else { return }

        let graphRate = player.outputFormat(forBus: 0).sampleRate
        let nextRate = nextFile.processingFormat.sampleRate

        if nextRate == graphRate {
            // Next file is 48 kHz — switch to the passthrough path for it.
            // Bump the generation so the old session's completions abandon; we don't call
            // player.stop() so the queue stays running. We are ALREADY on resampleQueue here, so
            // call the *Locked variant directly — stopEnhancedResampler() would resampleQueue.sync
            // onto ourselves and trap libdispatch (C-1 re-entrancy).
            stopEnhancedResamplerLocked()
            bumpTransitionCount(player: player)
            setLastFileURL(nextURL)
            scheduleFileChainingPassthrough(nextFile, player: player, resetFramePosition: true)
            // Arm the passthrough hook so the track after this one can also be gapless.
            armPassthroughNextTrack(player: player)
            logUX("gapless: resampler→passthrough seam '\(nextURL.lastPathComponent)'")
            return
        }

        // Next file is also rate-mismatched: continue the resampler chain.
        setLastFileURL(nextURL)
        startResamplerChainOrFallback(
            nextFile: nextFile, player: player, nextURL: nextURL,
            nextRate: nextRate, graphRate: graphRate
        )
    }

    /// Gapless roll for the 48 kHz passthrough sub-path.
    ///
    /// Called on `resampleQueue` after the current `scheduleFile` session's `.dataPlayedBack`
    /// callback fires (the hardware has played the last sample of the current track). Opens the
    /// next file and either chains another `scheduleFile` (48 kHz next) or starts the resampler
    /// (rate-mismatched next) — in both cases WITHOUT calling `player.stop()`.
    func rollPassthroughToNext(player: AVAudioPlayerNode) {
        guard let nextURL = consumeOnDeckURL(context: "passthrough") else { return }

        guard let nextFile = openNextFileOrRestart(nextURL, player: player) else { return }

        let graphRate = player.outputFormat(forBus: 0).sampleRate
        let nextRate = nextFile.processingFormat.sampleRate
        setLastFileURL(nextURL)

        if nextRate == graphRate {
            // Both current and next are 48 kHz: consecutive scheduleFile calls play back-to-back,
            // byte-exact. This is the spec's "consecutive scheduleFile" gapless path.
            bumpTransitionCount(player: player)
            scheduleFileChainingPassthrough(nextFile, player: player, resetFramePosition: true)
            armPassthroughNextTrack(player: player)
            logUX("gapless: passthrough→passthrough seam '\(nextURL.lastPathComponent)'")
            return
        }

        // Next track is rate-mismatched: start the resampler sub-path for it.
        startResamplerChainOrFallback(
            nextFile: nextFile, player: player, nextURL: nextURL,
            nextRate: nextRate, graphRate: graphRate
        )
    }

    // MARK: - Shared seam sub-steps (called on resampleQueue)

    /// Consume `onDeckURL` for a seam. Returns the armed URL, or `nil` if the queue is exhausted —
    /// in which case it marks the seam ended (sets `gaplessPlaybackEnded`, clears the auto-resume
    /// intent), exactly as the inline EOF guards did. MUST be called on `resampleQueue`.
    private func consumeOnDeckURL(context: String) -> URL? {
        guard let nextURL = onDeckURL else {
            gaplessPlaybackEnded = true
            enhancedPlayIntent = false // queue exhausted — don't auto-resume on a later config change
            logUX("gapless: \(context) EOF — no next track, playback ended")
            return nil
        }
        onDeckURL = nil // consume the armed URL
        return nextURL
    }

    /// Open `nextURL` for reading. On success returns the file (and releases the security scope,
    /// since `AVAudioFile` retains its own handle). On failure, falls back to a clean restart on
    /// the global queue — and if THAT also fails, sets `gaplessPlaybackEnded` on `resampleQueue`
    /// (the channel the VM polls) so the VM stops cleanly instead of polling a stopped engine
    /// (P3-3). Returns `nil` on the failure path. MUST be called on `resampleQueue`.
    private func openNextFileOrRestart(_ nextURL: URL, player: AVAudioPlayerNode) -> AVAudioFile? {
        let didAccess = nextURL.startAccessingSecurityScopedResource()

        guard let nextFile = try? AVAudioFile(forReading: nextURL) else {
            if didAccess { nextURL.stopAccessingSecurityScopedResource() }
            logUX("gapless: roll failed — cannot open '\(nextURL.lastPathComponent)'")
            // Degradation: fall back to a clean start on the global queue (stops + restarts,
            // brief gap). Sets playbackEnded if avEngine is gone (engine was shut down).
            DispatchQueue.global().async { [weak self] in
                guard let self else { return }
                guard let engine = self.avEngine else {
                    self.resampleQueue.async { self.gaplessPlaybackEnded = true }
                    return
                }
                // P3-3: surface the failure rather than discarding it via `try?`. If the clean
                // restart also fails (e.g. file unreadable, engine reconfiguring), set
                // `gaplessPlaybackEnded` on `resampleQueue` — the same seam-state channel the VM
                // polls — so the VM stops cleanly instead of polling a stopped engine forever.
                do {
                    try self.playFile(at: nextURL, engine: engine, playerNode: player)
                } catch {
                    logUX("gapless: fallback restart failed — "
                        + "'\(nextURL.lastPathComponent)': \(error.localizedDescription)")
                    self.resampleQueue.async { self.gaplessPlaybackEnded = true }
                }
            }
            return nil
        }
        // Security-scoped resource lifecycle: stop access after we open the file (AVAudioFile
        // retains its own file handle; we no longer need the security scope).
        if didAccess { nextURL.stopAccessingSecurityScopedResource() }
        return nextFile
    }

    /// Schedule `file` on the still-running player with a `.dataPlayedBack` completion that
    /// re-dispatches onto `resampleQueue` to fire `onPassthroughEOF` — the shared "consecutive
    /// scheduleFile" gapless primitive used by every passthrough seam (and the resampler→
    /// passthrough fallbacks). MUST be called on `resampleQueue`.
    private func scheduleFileChainingPassthrough(
        _ file: AVAudioFile,
        player: AVAudioPlayerNode,
        resetFramePosition: Bool
    ) {
        dispatchPrecondition(condition: .onQueue(resampleQueue))
        if resetFramePosition { file.framePosition = 0 }
        // Capture the CURRENT passthrough epoch (we're on resampleQueue, the owner; no bump —
        // a seam schedule replaces one whose completion already fired legitimately). A later
        // stop/seek/reschedule bumps the epoch, and this completion then abandons at fire time
        // instead of rolling the seam off a non-EOF `player.stop()` (wrong-song bug).
        let gen = passthroughGeneration
        player.scheduleFile(
            file, at: nil, completionCallbackType: .dataPlayedBack
        ) { [weak self, weak player] _ in
            guard let self, let livePlayer = player else { return }
            self.resampleQueue.async {
                guard gen == self.passthroughGeneration else { return } // superseded
                self.onPassthroughEOF?(livePlayer)
            }
        }
    }

    /// Continue (or start) the resampler chain for a rate-mismatched `nextFile`: build a fresh
    /// converter and prime it via `primeEnhancedResamplerLocked` (called DIRECTLY — never via
    /// `startEnhancedResampler`, preserving the C-1 deadlock guard). On any failure path
    /// (converter creation fails, or the prime schedules nothing for an empty file) it falls back
    /// to `scheduleFileChainingPassthrough` so the seam chain is preserved (S-1). MUST be called
    /// on `resampleQueue`.
    private func startResamplerChainOrFallback(
        nextFile: AVAudioFile,
        player: AVAudioPlayerNode,
        nextURL: URL,
        nextRate: Double,
        graphRate: Double
    ) {
        guard let converter = makeConverter(for: nextFile, player: player) else {
            // Converter creation failed: fall back to scheduleFile (brief gap, chain preserved).
            // Clear the OLD track's exhausted session first (the P1-2 rule, same as the
            // empty-prime branch below): leaving it non-nil misroutes a later seek/reestablish
            // to the resampler branch, whose stop() bumps only resampleGeneration — the live
            // passthrough schedule would fire under an unbumped epoch and roll the seam
            // (the wrong-song bug escaping through stale state; seam-fix review MAJOR-1).
            resampleSession = nil
            // S-1: the .dataPlayedBack completion keeps onPassthroughEOF firing for the next seam.
            bumpTransitionCount(player: player)
            armPassthroughNextTrack(player: player)
            scheduleFileChainingPassthrough(nextFile, player: player, resetFramePosition: false)
            logUX("gapless: →passthrough fallback seam "
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
            logUX("gapless: →resampler seam '\(nextURL.lastPathComponent)' "
                + "(\(Int(nextRate))→\(Int(graphRate)))")
            return
        }

        // primeEnhancedResamplerLocked scheduled nothing (empty file). Fall back to scheduleFile.
        // P1-2: clear resampleSession so a later seek/reestablish takes the passthrough branch
        // rather than the (now-stale) resampler branch. primeEnhancedResamplerLocked sets it
        // non-nil at the top of its prime even when 0 buffers are produced.
        resampleSession = nil
        // S-1: completion preserves the chain.
        bumpTransitionCount(player: player)
        armPassthroughNextTrack(player: player)
        scheduleFileChainingPassthrough(nextFile, player: player, resetFramePosition: false)
        logUX("gapless: →passthrough fallback seam "
            + "'\(nextURL.lastPathComponent)' (empty prime, scheduleFile)")
    }
}
