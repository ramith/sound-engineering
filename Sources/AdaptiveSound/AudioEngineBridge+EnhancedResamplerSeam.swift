@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge Enhanced resampler — read → convert → schedule iteration

/// The per-iteration read → convert → schedule machinery of the Enhanced streaming resampler,
/// split out of `AudioEngineBridge+EnhancedResampler.swift` to keep that file under the file-length
/// limit. Everything here runs on `resampleQueue` (the prime loop drives it via the
/// `resampleQueue.sync` in `startEnhancedResampler`; each `.dataConsumed` completion re-dispatches
/// the next iteration onto `resampleQueue`). The cancellation predicate (`isCurrent`) and the
/// `resampleGeneration` / `resampleSession` reads it performs are confined to `resampleQueue`,
/// exactly as before — this is a pure relocation, not a behaviour change.
extension AudioEngineBridge {
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

    // MARK: - Read → convert → schedule (one iteration)

    /// Read one input chunk, convert it via the pull API, and schedule the resulting 48 kHz buffer
    /// on `player` with a `.dataConsumed` completion that chains the next iteration. MUST run on
    /// `resampleQueue` (the prime loop runs there via the `resampleQueue.sync` in
    /// `startEnhancedResampler`; the completion re-dispatches onto `resampleQueue`).
    ///
    /// Returns `true` if a buffer was scheduled (more may follow); `false` at EOF / on error / when
    /// the generation no longer matches (the loop then stops chaining — no buffer is scheduled).
    /// When returning `false` due to EOF on the current session, fires `onResamplerEOF` (if set)
    /// so the gapless extension can roll into the next track without a gap.
    @discardableResult
    func readConvertSchedule(
        session: EnhancedResampleSession,
        player: AVAudioPlayerNode,
        generation: UInt64
    ) -> Bool {
        // Cancellation / supersession check (pre-read): a seek/stop/track-change bumped the
        // generation, so this session is stale — schedule nothing more (cleanly abandons chaining).
        guard isCurrent(generation: generation, session: session) else { return false }
        if session.reachedEnd {
            // Current session is exhausted. Fire the gapless EOF hook so the next track can be
            // scheduled without stopping the player — or, with NO hook armed (final track /
            // single track), surface the ended state (break-it BLOCKER-1). Runs on
            // resampleQueue, where all session state is serialized.
            fireResamplerEOFOrEnd(session: session, player: player)
            return false
        }

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
}
