import AVFoundation
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
/// completion thread or main. This file is engine code (not `@MainActor`), matching the bridge's
/// `DispatchQueue.global()` continuation pattern.
extension AudioEngineBridge {
    // MARK: - Tuning constants

    /// Input frames read from the file per chunk before conversion. 8192 input frames at 44.1 kHz is
    /// ~186 ms — large enough to keep the converter fed cheaply, small enough that a seek/stop is
    /// abandoned promptly. The matching output capacity is computed from the rate ratio + slack.
    private static let resampleInputChunkFrames: AVAudioFrameCount = 8192

    /// Number of buffers primed (scheduled) BEFORE `player.play()` so the player never underruns at
    /// start and there is no startup delay. Three ~186 ms chunks ≈ half a second of lead.
    private static let resamplePrimeCount: Int = 3

    /// Slack frames added to the estimated output capacity per chunk. Absorbs the resampler's
    /// interpolation tail so the final block is never truncated at a rate-conversion boundary.
    private static let resampleOutputCapacitySlack: AVAudioFrameCount = 4096

    // MARK: - Cancellation predicate

    /// Returns `true` when `generation` still matches the live epoch AND `session` is still the
    /// active session — i.e. no seek / stop / track-change has superseded this iteration.
    ///
    /// Must be called on `resampleQueue` (where `resampleGeneration` and `resampleSession` are
    /// exclusively mutated). The predicate is intentionally a simple inline read so the check occurs
    /// at the exact point of the `guard` call-site — no defer, no async, no re-ordering.
    private func isCurrent(generation: UInt64, session: EnhancedResampleSession) -> Bool {
        generation == resampleGeneration && resampleSession === session
    }

    // MARK: - Start

    /// Start streaming `audioFile` through the high-quality resampler from `startFrame`.
    ///
    /// Returns `true` if the converter was created and the loop primed + started (the caller must
    /// NOT then call the `scheduleFile` path); returns `false` if the converter could not be created
    /// (the caller MUST fall back to `scheduleFile`, accepting the engine's default SRC, and log it).
    ///
    /// Must be called OFF the audio thread (it allocates buffers + creates the converter). Callers:
    /// `playFile` (from frame 0) and the Enhanced resampled-seek branch (from the seek target frame).
    /// All converter access + scheduling here happens on `resampleQueue` (via `sync`) so the
    /// converter is only ever touched from that one serial queue.
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

        // Prime + start synchronously on the serial queue: this serializes all converter access and
        // gives the caller a definite success/failure result for the fallback decision. Priming
        // before play() gives the player a cushion (no underrun, no startup delay).
        var primed = 0
        resampleQueue.sync {
            // Position the file read head (0 for a fresh play; the seek target for a resampled seek).
            let totalFrames = audioFile.length
            let clampedStart = max(0, min(startFrame, totalFrames))
            audioFile.framePosition = clampedStart

            // Bump the generation so any prior session's in-flight iterations abandon themselves,
            // then capture THIS session's generation for the loop to compare against.
            resampleGeneration &+= 1
            let generation = resampleGeneration
            resampleSession = session

            for _ in 0 ..< Self.resamplePrimeCount {
                let scheduled = readConvertSchedule(
                    session: session, player: player, generation: generation
                )
                if !scheduled { break }
                primed += 1
            }
        }

        // If the very first read produced nothing (e.g. empty/zero-length file), fall back so the
        // user still hears the file via the proven path.
        guard primed > 0 else {
            resampleQueue.sync { resampleSession = nil }
            NSLog("[AudioEngineBridge] resampler primed 0 buffers; caller falls back to scheduleFile")
            return false
        }

        player.play()
        return true
    }

    // MARK: - Read → convert → schedule (one iteration)

    /// Read one input chunk, convert it via the pull API, and schedule the resulting 48 kHz buffer
    /// on `player` with a `.dataConsumed` completion that chains the next iteration. MUST run on
    /// `resampleQueue` (the prime loop runs there via the `resampleQueue.sync` in
    /// `startEnhancedResampler`; the completion re-dispatches onto `resampleQueue`).
    ///
    /// Returns `true` if a buffer was scheduled (more may follow); `false` at EOF / on error / when
    /// the generation no longer matches (the loop then stops chaining — no buffer is scheduled).
    @discardableResult
    private func readConvertSchedule(
        session: EnhancedResampleSession,
        player: AVAudioPlayerNode,
        generation: UInt64
    ) -> Bool {
        // Cancellation / supersession check (pre-read): a seek/stop/track-change bumped the
        // generation, so this session is stale — schedule nothing more (cleanly abandons chaining).
        guard isCurrent(generation: generation, session: session) else { return false }
        guard !session.reachedEnd else { return false }

        guard let inputBuffer = readChunk(session: session),
              let outputBuffer = convertChunk(session: session, inputBuffer: inputBuffer)
        else {
            return false
        }

        // Re-check AFTER the (potentially slow) convert: a seek may have landed while we were
        // converting. If so, drop this buffer on the floor rather than schedule stale audio.
        guard isCurrent(generation: generation, session: session) else { return false }
        guard outputBuffer.frameLength > 0 else { return false }

        // Schedule the converted 48 kHz buffer. `.dataConsumed` fires when the player has consumed
        // it; we then chain the next iteration on the serial queue. The completion does NO converter
        // work itself — it only re-dispatches — so we never touch the converter off `resampleQueue`.
        player.scheduleBuffer(outputBuffer, completionCallbackType: .dataConsumed) { [weak self, weak player] _ in
            guard let self, let player else { return }
            self.resampleQueue.async {
                _ = self.readConvertSchedule(session: session, player: player, generation: generation)
            }
        }
        return true
    }

    /// Allocate + fill one input chunk from the file. A read error or a true zero-frame read marks
    /// the session done (so the next convert flushes the resampler tail). Returns `nil` only if the
    /// input buffer could not be allocated. Runs on `resampleQueue`.
    private func readChunk(session: EnhancedResampleSession) -> AVAudioPCMBuffer? {
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: session.inputFormat, frameCapacity: session.inputChunkFrames
        ) else {
            return nil
        }
        do {
            try session.audioFile.read(into: inputBuffer, frameCount: session.inputChunkFrames)
        } catch {
            session.reachedEnd = true
        }
        if inputBuffer.frameLength == 0 {
            session.reachedEnd = true
        }
        return inputBuffer
    }

    /// Convert `inputBuffer` through the session's converter into a freshly sized output buffer.
    /// Returns the converted 48 kHz buffer, or `nil` on allocation/conversion error (the session is
    /// marked done on a hard error). Runs on `resampleQueue`.
    private func convertChunk(
        session: EnhancedResampleSession,
        inputBuffer: AVAudioPCMBuffer
    ) -> AVAudioPCMBuffer? {
        // Output capacity for a chunk of inFrames at the rate ratio, plus generous slack for the
        // resampler's interpolation tail (avoids a truncated final block).
        let rateRatio = session.outputFormat.sampleRate / session.inputFormat.sampleRate
        let estimatedOut = Double(session.inputChunkFrames) * rateRatio
        let outCapacity = AVAudioFrameCount(estimatedOut.rounded(.up)) + Self.resampleOutputCapacitySlack
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: session.outputFormat, frameCapacity: outCapacity
        ) else {
            return nil
        }

        // The pull input block hands the converter the just-read chunk exactly once per convert()
        // call; subsequent pulls report end/no-data so the converter flushes its interpolation tail.
        session.inputConsumed = false
        let inputBlock = makeInputBlock(session: session, inputBuffer: inputBuffer)

        var conversionError: NSError?
        let status = session.converter.convert(
            to: outputBuffer, error: &conversionError, withInputFrom: inputBlock
        )

        switch status {
        case .error:
            if let conversionError {
                NSLog("[AudioEngineBridge] resampler convert error: \(conversionError); ending stream")
            }
            session.reachedEnd = true
            return nil
        case .endOfStream:
            session.reachedEnd = true
        case .haveData, .inputRanDry:
            break
        @unknown default:
            break
        }
        return outputBuffer
    }

    /// Build the `AVAudioConverterInputBlock` that hands `inputBuffer` to the converter exactly once
    /// for the current convert() call, then reports end-of-stream / no-data so the converter does not
    /// block and flushes its tail at EOF. Uses `session.inputConsumed` as the once-latch.
    private func makeInputBlock(
        session: EnhancedResampleSession,
        inputBuffer: AVAudioPCMBuffer
    ) -> AVAudioConverterInputBlock {
        { [weak session] _, outStatus in
            guard let session else {
                outStatus.pointee = .endOfStream
                return nil
            }
            if session.inputConsumed || inputBuffer.frameLength == 0 {
                outStatus.pointee = session.reachedEnd ? .endOfStream : .noDataNow
                return nil
            }
            session.inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
    }

    // MARK: - Seek (resampled session)

    /// Restart the streaming resampler at `seconds` for an active resampled session. MUST run off
    /// the audio thread (it stops the player, resets the converter, and re-primes). Bumps the
    /// generation so every in-flight buffer from before the seek is abandoned, then re-primes +
    /// plays from the target frame. No-op (returns false) if no resampled session is active.
    @discardableResult
    func seekEnhancedResampler(to seconds: Double, player: AVAudioPlayerNode) -> Bool {
        guard let session = resampleSession else { return false }

        // Bump generation FIRST so any completion that fires mid-seek schedules nothing onto the
        // about-to-be-restarted player. Stop the player to flush its queued (now-stale) buffers.
        resampleGeneration &+= 1
        player.stop()

        let fileRate = session.inputFormat.sampleRate
        guard fileRate > 0 else { return false }

        let target = max(seconds, 0)
        let targetFrame = AVAudioFramePosition(target * fileRate)
        let totalFrames = session.audioFile.length
        guard targetFrame >= 0, targetFrame < totalFrames else { return false }

        // Reset the converter's internal rate-conversion state so the post-seek stream does not
        // inherit pre-seek interpolation history (which would smear the join).
        session.converter.reset()
        session.reachedEnd = false

        // Restart the loop from the target frame. startEnhancedResampler bumps the generation again
        // (harmless) and re-primes + plays. It re-uses the same open AVAudioFile via a fresh session.
        return startEnhancedResampler(
            audioFile: session.audioFile, player: player, startFrame: targetFrame
        )
    }

    // MARK: - Stop / teardown

    /// Stop the streaming-resampler loop: bump the generation so every in-flight read→convert→
    /// schedule iteration (and every pending completion) abandons itself, then drop the session.
    /// Safe to call when no session is active. Call BEFORE mutating shared graph state (stop,
    /// shutdown, reconfigure, track change) so no buffer schedules onto a torn-down graph.
    func stopEnhancedResampler() {
        resampleGeneration &+= 1
        resampleSession = nil
    }
}

// MARK: - EnhancedResampleSession

/// Per-playback-session state for the Enhanced streaming resampler. A class (reference type) so the
/// completion-chained iterations and the input pull block share one instance; held by the bridge as
/// `resampleSession` and only ever mutated on `resampleQueue`.
final class EnhancedResampleSession {
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
