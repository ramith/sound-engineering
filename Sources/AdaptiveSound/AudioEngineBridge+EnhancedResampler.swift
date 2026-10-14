import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge Enhanced streaming-resampler path

/// Replaces AVAudioEngine's hidden default sample-rate conversion on the ENHANCED playback path
/// with an explicit, high-quality streaming resampler: `StreamingResampler` (AudioFormatKit) —
/// Apple's `AVAudioConverter` at the Mastering algorithm and max quality, configured in that one
/// place, which `make gate`'s SRC check measures (R1.1-A, council C-26; it was the Normal algorithm,
/// on a "Mastering would stall live playback" premise that was never measured and is false).
///
/// Scope is deliberately bounded to RATE-MISMATCHED files: it runs only when the opened file's
/// sample rate differs from the 48 kHz engine-graph rate. When the file is already 48 kHz the
/// caller keeps the proven `scheduleFile` path UNCHANGED (it is already a rate passthrough; the
/// engine performs no SRC). So this new code's blast radius is exactly "files whose rate != 48 kHz".
///
/// Design:
/// - One `EnhancedResampleSession` per playback session: the file and its converter, `from:` the
///   file's processing format (file rate, N-channel float) `to:` `playerNode.outputFormat(forBus: 0)`
///   (48 kHz, N-channel float). Matching the player's negotiated output format means
///   `scheduleBuffer` triggers NO further engine SRC.
/// - A background SERIAL queue (`resampleQueue`) reads file chunks into an input buffer, converts
///   them (`StreamingResampler.convert`, which keeps the rate-conversion state across chunks), and
///   `scheduleBuffer(_, completionCallbackType: .dataConsumed)` chaining: each completion
///   dispatches the next read→convert→schedule on the serial queue.
/// - A generation/epoch counter (`resampleGeneration`) makes seek/stop/track-change cancellation
///   correct: each iteration captures the generation it began under and bails if it has changed.
/// - NEVER breaks playback: if the converter can't be created the caller falls back to `scheduleFile`.
///
/// Concurrency: every converter access + every `scheduleBuffer` call happens on `resampleQueue`.
/// Completion callbacks (delivered on an arbitrary AVAudioEngine thread) do nothing but re-dispatch
/// onto `resampleQueue`, so the converter is touched from exactly one thread and we never block the
/// completion thread or main. This file is engine code (not `@MainActor`); its off-queue entry
/// points (`startEnhancedResampler`, `seekEnhancedResampler`) are invoked from the serial
/// `engineQueue` / `configChangeQueue` transport bodies, never from `resampleQueue` itself.
extension AudioEngineBridge {
    // MARK: - Tuning constants

    /// Number of buffers primed (scheduled) BEFORE `player.play()` so the player never underruns at
    /// start and there is no startup delay. Three ~186 ms chunks ≈ half a second of lead.
    private static let resamplePrimeCount: Int = 3

    // MARK: - Start

    /// Start streaming `audioFile` through the high-quality resampler from `startFrame`.
    ///
    /// MUST be called OFF `resampleQueue` (it creates a converter, then calls
    /// `resampleQueue.sync { primeEnhancedResamplerLocked(...) }`). Callers: `playFile` (frame 0)
    /// and `seekEnhancedResampler` (seek-target frame). Seam handlers that are already on
    /// `resampleQueue` must call `primeEnhancedResamplerLocked` directly to avoid a deadlock.
    ///
    /// Returns `true` if the converter was created and the prime loop scheduled at least one buffer
    /// (the caller must NOT then schedule via `scheduleFile`); returns `false` if the converter
    /// could not be created (the caller MUST fall back to `scheduleFile`).
    @discardableResult
    func startEnhancedResampler(
        audioFile: AVAudioFile,
        player: AVAudioPlayerNode,
        startFrame: AVAudioFramePosition
    ) -> Bool {
        guard let session = EnhancedResampleSession(file: audioFile, outputFormat: player.outputFormat(forBus: 0))
        else {
            return false // the caller falls back to scheduleFile
        }

        // Prime synchronously on the serial queue so the caller gets a definite success/failure
        // result for the fallback decision. Priming before play() gives the player a cushion.
        // This is an OFF-queue entry point — the sync here is safe. Seam handlers that are
        // already on resampleQueue call primeEnhancedResamplerLocked directly (no sync).
        var primed = 0
        resampleQueue.sync {
            primed = self.primeEnhancedResamplerLocked(session: session, player: player, startFrame: startFrame)
        }

        // If the very first read produced nothing (e.g. empty/zero-length file), fall back so the
        // user still hears the file via the proven path.
        guard primed > 0 else {
            resampleQueue.sync { resampleSession = nil }
            NSLog("[AudioEngineBridge] resampler primed 0 buffers; caller falls back to scheduleFile")
            return false
        }

        // Start the player only when it is not already running. On a gapless roll into a new
        // resampler session the player is still playing the tail of the previous session — calling
        // play() again would reset the hardware clock and introduce a gap. On a fresh startAudio
        // or a seek-triggered re-prime the player will be stopped so this still starts it.
        if !player.isPlaying {
            player.play()
        }
        return true
    }

    /// Prime-loop body for the resampler. MUST be called on `resampleQueue`; enforced by
    /// `dispatchPrecondition`. Positions the file read-head, bumps the generation, installs the
    /// session, and schedules up to `resamplePrimeCount` initial buffers.
    ///
    /// Returns the number of buffers successfully scheduled (0 means the file is empty / unusable;
    /// the caller should fall back to `scheduleFile`).
    ///
    /// Called from:
    /// - `startEnhancedResampler` (off-queue entry point) via `resampleQueue.sync`
    /// - `rollResamplerToNext` / `rollPassthroughToNext` (seam handlers, already on `resampleQueue`)
    ///   — these call this method directly to avoid a deadlock from a sync-on-self.
    @discardableResult
    func primeEnhancedResamplerLocked(
        session: EnhancedResampleSession,
        player: AVAudioPlayerNode,
        startFrame: AVAudioFramePosition
    ) -> Int {
        dispatchPrecondition(condition: .onQueue(resampleQueue))

        // Position the file read head (0 for a fresh play; the seek target for a resampled seek).
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

    // MARK: - Seek (resampled session)

    /// Restart the streaming resampler at `seconds` for an active resampled session. MUST run off
    /// `resampleQueue` (it stops the player, resets the converter, and re-primes via
    /// `startEnhancedResampler`, which does its own `resampleQueue.sync` for the prime).
    /// Bumps the generation so every in-flight buffer from before the seek is abandoned, then
    /// re-primes + plays from the target frame. No-op (returns false) if no resampled session is
    /// active.
    ///
    /// Concurrency: callers are `seek()` (engineQueue) and
    /// `reestablishEnhancedAfterConfigChange` (configChangeQueue) — both off resampleQueue,
    /// so the resampleQueue.sync here is deadlock-safe.
    @discardableResult
    func seekEnhancedResampler(to seconds: Double, player: AVAudioPlayerNode) -> Bool {
        // Capture the session and perform all mutations under the queue's lock to avoid
        // races with in-flight read→convert→schedule iterations on resampleQueue.
        var capturedSession: EnhancedResampleSession?
        var targetFrame: AVAudioFramePosition = 0

        resampleQueue.sync {
            guard let session = resampleSession else { return }
            capturedSession = session

            // Bump BOTH generations FIRST so any completion that fires mid-seek schedules
            // nothing onto the about-to-be-restarted player. The passthrough bump is
            // defense-in-depth (review MAJOR-1): if stale state ever routes a passthrough
            // session through THIS branch, its live .dataPlayedBack completion must abandon
            // on the stop below rather than roll the seam.
            resampleGeneration &+= 1
            passthroughGeneration &+= 1

            let fileRate = session.resampler.inputFormat.sampleRate
            guard fileRate > 0 else { capturedSession = nil; return }

            let target = max(seconds, 0)
            let frame = AVAudioFramePosition(target * fileRate)
            let totalFrames = session.audioFile.length
            guard frame >= 0, frame < totalFrames else { capturedSession = nil; return }
            targetFrame = frame
        }

        guard let session = capturedSession else { return false }

        // Stop the player AFTER the generation bump (generation bump is inside the sync above).
        // The stop flushes the player's queued stale buffers. Done outside the sync so the
        // hardware callback isn't stalled while we hold resampleQueue.
        player.stop()

        // Restart the loop from the target frame. startEnhancedResampler builds a NEW session (a
        // fresh converter: no pre-seek history smears the join), bumps the generation again
        // (harmless — the old session's completions were already abandoned by the bump above) and
        // re-primes + plays. It does its own resampleQueue.sync for the prime, which
        // is safe because we are NOT currently holding resampleQueue here (we exited the sync
        // block above before calling this).
        return startEnhancedResampler(
            audioFile: session.audioFile, player: player, startFrame: targetFrame
        )
    }

    // MARK: - Stop / teardown

    /// Stop the streaming-resampler loop: bump the generation so every in-flight read→convert→
    /// schedule iteration (and every pending completion) abandons itself, then drop the session
    /// and clear both gapless EOF hooks. Safe to call when no session is active. Call BEFORE
    /// mutating shared graph state (stop, shutdown, reconfigure, track change) so no buffer
    /// schedules onto a torn-down graph. Both EOF hooks are cleared so stale handlers cannot fire
    /// on a new session after a seek, stop, or new-track interrupt.
    ///
    /// NOTE: `stopEnhancedPlayback` calls this first, so it also sees `onPassthroughEOF` cleared.
    /// The explicit `resampleQueue.async` clear in `stopEnhancedPlayback` is a belt-and-suspenders
    /// guard for the rare path where only the passthrough hook is live (no resampler session).
    ///
    /// Concurrency: off-queue callers (stopAudio, stopEnhancedPlayback, playFile, reconfigure,
    /// shutdown) run on engineQueue / configChangeQueue — never on resampleQueue — so the
    /// `resampleQueue.sync` here is deadlock-safe. Callers ALREADY on resampleQueue (the gapless
    /// seam handlers in GaplessRoll.swift) MUST call `stopEnhancedResamplerLocked()` directly —
    /// the same re-entrancy discipline as `primeEnhancedResamplerLocked` (C-1). Calling this
    /// syncing variant from resampleQueue traps libdispatch ("dispatch_sync on a queue already
    /// owned by current thread").
    func stopEnhancedResampler() {
        resampleQueue.sync { stopEnhancedResamplerLocked() }
    }

    /// Teardown body run WITHOUT dispatching — the caller MUST already be on `resampleQueue`.
    /// Bumps BOTH generations (in-flight resampler iterations AND pending passthrough
    /// `.dataPlayedBack` completions abandon themselves — `player.stop()` fires the latter,
    /// indistinguishable from a real EOF), drops the session, and clears both gapless EOF
    /// hooks. Used by the gapless seam handlers (which run on resampleQueue); off-queue
    /// callers use `stopEnhancedResampler()`, which wraps this in `resampleQueue.sync`.
    func stopEnhancedResamplerLocked() {
        dispatchPrecondition(condition: .onQueue(resampleQueue))
        resampleGeneration &+= 1
        passthroughGeneration &+= 1
        resampleSession = nil
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
