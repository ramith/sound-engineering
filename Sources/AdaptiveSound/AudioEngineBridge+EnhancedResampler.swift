import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge Enhanced streaming-resampler path

/// The Enhanced path for a file whose rate is not the graph's 48 kHz: the file is read in chunks,
/// converted by `StreamingResampler` (Apple's Mastering-quality converter, configured once in
/// AudioFormatKit — the code `make gate`'s SRC check measures), and scheduled on the player. A file
/// at the graph's rate never comes here: it plays through (`schedulePassthrough`). Starts, seeks and
/// re-establishes reach it through the one Enhanced restart (`commitEnhanced`,
/// AudioEngineBridge+EnhancedRestart); the gapless seams through `primeEnhancedResamplerLocked`.
///
/// Design:
/// - One `EnhancedResampleSession` per run of a file — each start, seek, re-establish and seam makes
///   a new one: the open file and its converter, file format → `player.outputFormat(forBus: 0)`
///   (48 kHz, N-channel float), so `scheduleBuffer` triggers no further engine conversion.
/// - The chain runs on the serial `resampleQueue`: read a chunk → convert → `scheduleBuffer(…,
///   .dataConsumed)`; each completion only re-dispatches the next iteration onto the queue.
/// - `resampleGeneration` cancels: every iteration captures the generation it began under and stops
///   the moment a seek / stop / track change bumped it.
///
/// Concurrency: the converter and every `scheduleBuffer` are touched only on `resampleQueue`. The
/// completions (delivered on an arbitrary AVAudioEngine thread) do nothing but re-dispatch onto it,
/// so the converter is touched from exactly one thread and no completion thread or main is blocked.
extension AudioEngineBridge {
    // MARK: - Tuning constants

    /// Buffers primed (scheduled) BEFORE `player.play()` so the player never underruns at start:
    /// three chunks ≈ half a second of lead at 44.1 kHz.
    private static let resamplePrimeCount: Int = 3

    // MARK: - Prime

    /// Prime-loop body for the resampler. MUST be called on `resampleQueue`; enforced by
    /// `dispatchPrecondition`. Positions the file read-head, bumps the generation, installs the
    /// session, and schedules up to `resamplePrimeCount` initial buffers. Does not play: the caller
    /// starts the player (a restart), or it is already running (a gapless seam).
    ///
    /// Returns the number of buffers scheduled (0: nothing could be read or converted from
    /// `startFrame` — the caller ends the track or falls back).
    ///
    /// Called from `commitEnhanced` (off-queue, via `resampleQueue.sync`) and the gapless seam
    /// handlers (already on `resampleQueue`, so they call it directly — never through a sync, C-1).
    @discardableResult
    func primeEnhancedResamplerLocked(
        session: EnhancedResampleSession,
        player: AVAudioPlayerNode,
        startFrame: AVAudioFramePosition
    ) -> Int {
        dispatchPrecondition(condition: .onQueue(resampleQueue))

        // Position the file read head (0 for a fresh play; the place for a restart).
        let totalFrames = session.audioFile.length
        session.audioFile.framePosition = max(0, min(startFrame, totalFrames))

        // Bump the generation so any prior session's in-flight iterations abandon themselves,
        // then capture THIS session's generation for the loop to compare against.
        resampleGeneration &+= 1
        let generation = resampleGeneration
        resampleSession = session

        var primed = 0
        for _ in 0 ..< Self.resamplePrimeCount {
            let scheduled = readConvertSchedule(
                session: session, player: player, generation: generation
            )
            if !scheduled {
                break
            }
            primed += 1
        }
        return primed
    }

    // MARK: - Supersede / stop / teardown

    /// Supersede whatever the player has scheduled: bump BOTH generations — every in-flight resampler
    /// iteration and every pending passthrough `.dataPlayedBack` completion abandons itself
    /// (`player.stop()` fires the latter, indistinguishable from a real end) — and drop the session.
    /// The on-deck slot and the EOF hooks stay: the same playback may go on from a new place (a
    /// seek). Returns the new passthrough epoch, for the schedule that replaces the old one. MUST be
    /// called on `resampleQueue`.
    @discardableResult
    func supersedeEnhancedScheduleLocked() -> UInt64 {
        dispatchPrecondition(condition: .onQueue(resampleQueue))
        resampleGeneration &+= 1
        passthroughGeneration &+= 1
        resampleSession = nil
        return passthroughGeneration
    }

    /// Stop the streaming-resampler loop and end the playback's seam state: supersede the schedule
    /// and clear both gapless EOF hooks, so no stale handler fires on a later session after a stop,
    /// a new track or the end. Safe to call when no session is active. Call BEFORE mutating shared
    /// graph state (stop, shutdown, reconfigure, track change) so no buffer schedules onto a
    /// torn-down graph.
    ///
    /// Concurrency: off-queue callers (stopAudio, stopEnhancedPlayback, playFile, reconfigure,
    /// shutdown) run on engineQueue / configChangeQueue — never on resampleQueue — so the
    /// `resampleQueue.sync` here is deadlock-safe. Callers ALREADY on resampleQueue (the gapless
    /// seam handlers) MUST call `stopEnhancedResamplerLocked()` directly — the same re-entrancy
    /// discipline as `primeEnhancedResamplerLocked` (C-1): a sync onto the current queue traps.
    func stopEnhancedResampler() {
        resampleQueue.sync { stopEnhancedResamplerLocked() }
    }

    /// The body of `stopEnhancedResampler`, for a caller already on `resampleQueue`.
    func stopEnhancedResamplerLocked() {
        supersedeEnhancedScheduleLocked()
        onResamplerEOF = nil
        onPassthroughEOF = nil
    }
}

// MARK: - EnhancedResampleSession

/// One run of a file through the Enhanced streaming resampler: the open file and its converter. A
/// class (reference type) so the completion-chained iterations share one instance; held by the
/// bridge as `resampleSession` and only ever mutated on `resampleQueue`.
///
/// `@unchecked Sendable` invariant: this session is created on a bridge queue and *only ever used
/// and mutated on* `resampleQueue` once installed. The completion closures that capture it do
/// nothing but re-dispatch onto `resampleQueue`. Single-serial-queue confinement is the external
/// synchronization that makes `@unchecked` truthful; it is never touched on the render/tap (RT)
/// thread, so no allocation/lock is added there.
final class EnhancedResampleSession: @unchecked Sendable {
    /// The converter: file format → the player's format (the Mastering `StreamingResampler`).
    let resampler: StreamingResampler

    /// The open source file, read sequentially chunk-by-chunk.
    let audioFile: AVAudioFile

    /// Set once the file is exhausted / the converter signals end — stops further chaining.
    var reachedEnd: Bool = false

    /// `nil` when Apple has no converter from `file`'s processing format to `outputFormat`.
    init?(file: AVAudioFile, outputFormat: AVAudioFormat) {
        guard let resampler = StreamingResampler(from: file.processingFormat, to: outputFormat) else {
            NSLog("[AudioEngineBridge] no converter \(file.processingFormat) -> \(outputFormat)")
            return nil
        }
        self.resampler = resampler
        audioFile = file
    }
}
