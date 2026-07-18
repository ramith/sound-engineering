@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge Enhanced streaming-resampler path

/// Replaces AVAudioEngine's hidden default sample-rate conversion on the ENHANCED playback path
/// with an explicit, high-quality streaming resampler (`AVAudioConverter` at `.max` quality, the
/// default Normal algorithm — NOT `.mastering`, which is an offline/high-latency algorithm that
/// would stall live playback).
///
/// Scope is deliberately bounded to RATE-MISMATCHED files: it runs only when the opened file's
/// sample rate differs from the 48 kHz engine-graph rate. When the file is already 48 kHz the
/// caller keeps the proven `scheduleFile` path UNCHANGED (it is already a rate passthrough; the
/// engine performs no SRC). So this new code's blast radius is exactly "files whose rate != 48 kHz".
///
/// Design:
/// - One `AVAudioConverter` per playback session, `from:` the file's processing format (file rate,
///   N-channel float) `to:` `playerNode.outputFormat(forBus: 0)` (48 kHz, N-channel float). Matching
///   the player's negotiated output format means `scheduleBuffer` triggers NO further engine SRC.
/// - A background SERIAL queue (`resampleQueue`) reads file chunks into an input buffer, converts via
///   the pull API `convert(to:error:withInputFrom:)` (which maintains rate-conversion state across
///   calls), and `scheduleBuffer(_, completionCallbackType: .dataConsumed)` chaining: each completion
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

    /// Input frames read from the file per chunk before conversion. 8192 input frames at 44.1 kHz is
    /// ~186 ms — large enough to keep the converter fed cheaply, small enough that a seek/stop is
    /// abandoned promptly. The matching output capacity is computed from the rate ratio + slack.
    /// Internal (not private) so the gapless seam handlers can construct `EnhancedResampleSession`
    /// with the same chunk size without duplicating the constant.
    static let resampleInputChunkFrames: AVAudioFrameCount = 8192

    /// Number of buffers primed (scheduled) BEFORE `player.play()` so the player never underruns at
    /// start and there is no startup delay. Three ~186 ms chunks ≈ half a second of lead.
    private static let resamplePrimeCount: Int = 3

    /// Slack frames added to the estimated output capacity per chunk. Absorbs the resampler's
    /// interpolation tail so the final block is never truncated at a rate-conversion boundary.
    /// Internal (not private) so `convertChunk` in `AudioEngineBridge+EnhancedResamplerSeam.swift`
    /// can size the output buffer with the same slack.
    static let resampleOutputCapacitySlack: AVAudioFrameCount = 4096

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
        let outputFormat = player.outputFormat(forBus: 0)
        let inputFormat = audioFile.processingFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            NSLog("[AudioEngineBridge] AVAudioConverter creation failed (\(inputFormat.sampleRate)"
                + " -> \(outputFormat.sampleRate)); caller falls back to scheduleFile")
            return false
        }
        // Best REAL-TIME quality. Deliberately leave the algorithm at the default (Normal) — the
        // `.mastering` algorithm is offline/high-latency and would stall live playback.
        converter.sampleRateConverterQuality = .max

        let session = EnhancedResampleSession(
            converter: converter,
            audioFile: audioFile,
            inputFormat: inputFormat,
            outputFormat: outputFormat,
            inputChunkFrames: Self.resampleInputChunkFrames
        )

        // Prime synchronously on the serial queue so the caller gets a definite success/failure
        // result for the fallback decision. Priming before play() gives the player a cushion.
        // This is an OFF-queue entry point — the sync here is safe. Seam handlers that are
        // already on resampleQueue call primeEnhancedResamplerLocked directly (no sync).
        var primed = 0
        resampleQueue.sync {
            primed = self.primeEnhancedResamplerLocked(
                session: session, audioFile: audioFile, player: player, startFrame: startFrame
            )
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
        audioFile: AVAudioFile,
        player: AVAudioPlayerNode,
        startFrame: AVAudioFramePosition
    ) -> Int {
        dispatchPrecondition(condition: .onQueue(resampleQueue))

        // Position the file read head (0 for a fresh play; the seek target for a resampled seek).
        let totalFrames = audioFile.length
        let clampedStart = max(0, min(startFrame, totalFrames))
        audioFile.framePosition = clampedStart

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
            if !scheduled { break }
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

            let fileRate = session.inputFormat.sampleRate
            guard fileRate > 0 else { capturedSession = nil; return }

            let target = max(seconds, 0)
            let frame = AVAudioFramePosition(target * fileRate)
            let totalFrames = session.audioFile.length
            guard frame >= 0, frame < totalFrames else { capturedSession = nil; return }
            targetFrame = frame

            // Reset the converter's internal rate-conversion state so the post-seek stream does
            // not inherit pre-seek interpolation history (which would smear the join).
            session.converter.reset()
            session.reachedEnd = false
        }

        guard let session = capturedSession else { return false }

        // Stop the player AFTER the generation bump (generation bump is inside the sync above).
        // The stop flushes the player's queued stale buffers. Done outside the sync so the
        // hardware callback isn't stalled while we hold resampleQueue.
        player.stop()

        // Restart the loop from the target frame. startEnhancedResampler bumps the generation
        // again (harmless — the old session's completions were already abandoned by the bump
        // above) and re-primes + plays. It does its own resampleQueue.sync for the prime, which
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

/// Per-playback-session state for the Enhanced streaming resampler. A class (reference type) so the
/// completion-chained iterations and the input pull block share one instance; held by the bridge as
/// `resampleSession` and only ever mutated on `resampleQueue`.
///
/// `@unchecked Sendable` invariant: this session is created and *only ever mutated on*
/// `resampleQueue`. The completion / input closures that capture it either run on
/// `resampleQueue` or do nothing but re-dispatch onto it. Single-serial-queue confinement
/// is the external synchronization that makes `@unchecked` truthful; it is never touched
/// on the render/tap (RT) thread, so no allocation/lock is added there.
final class EnhancedResampleSession: @unchecked Sendable {
    /// The high-quality streaming converter (file rate → 48 kHz, N→N), `.max` quality, Normal algo.
    let converter: AVAudioConverter

    /// The open source file, read sequentially chunk-by-chunk. Re-used across a resampled seek
    /// (its `framePosition` is repositioned). Owned for the session's lifetime.
    let audioFile: AVAudioFile

    /// File processing format (file rate, N-channel float) — the converter input + input buffers.
    let inputFormat: AVAudioFormat

    /// Player output format (48 kHz, N-channel float) — the converter output + scheduled buffers.
    let outputFormat: AVAudioFormat

    /// Input frames read per chunk (the converter's input buffer capacity).
    let inputChunkFrames: AVAudioFrameCount

    /// Set once the file is exhausted / the converter signals end — stops further chaining.
    var reachedEnd: Bool = false

    /// Per-`convert()`-call latch: ensures the just-read chunk is handed to the converter exactly
    /// once, after which the input block reports end/no-data so the converter flushes its tail.
    var inputConsumed: Bool = false

    init(
        converter: AVAudioConverter,
        audioFile: AVAudioFile,
        inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        inputChunkFrames: AVAudioFrameCount
    ) {
        self.converter = converter
        self.audioFile = audioFile
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.inputChunkFrames = inputChunkFrames
    }
}
