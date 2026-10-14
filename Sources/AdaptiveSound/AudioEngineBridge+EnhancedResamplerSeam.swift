import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge Enhanced resampler — read → convert → schedule iteration

/// The per-iteration read → convert → schedule machinery of the Enhanced streaming resampler.
/// Everything here runs on `resampleQueue` (the prime loop drives it — from
/// `startEnhancedResampler`'s `resampleQueue.sync`, or a seam handler already on the queue; each
/// `.dataConsumed` completion re-dispatches the next iteration onto `resampleQueue`). The
/// cancellation predicate (`isCurrent`) and the `resampleGeneration` / `resampleSession` reads it
/// performs are confined to `resampleQueue`. The conversion itself is `StreamingResampler`'s
/// (AudioFormatKit), which the `make gate` SRC check drives in the same chunks.
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
    /// `resampleQueue` (the prime loop runs there; the completion re-dispatches onto it).
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
        let frames = StreamingResampler.inputChunkFrames
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: session.resampler.inputFormat, frameCapacity: frames
        ) else {
            return nil
        }
        do {
            try session.audioFile.read(into: inputBuffer, frameCount: frames)
        } catch {
            session.reachedEnd = true
        }
        if inputBuffer.frameLength == 0 {
            session.reachedEnd = true
        }
        return inputBuffer
    }

    /// Convert `inputBuffer` through the session's `StreamingResampler` (the chunk it takes; at the
    /// end of the file, the flush). Returns the converted 48 kHz buffer, or `nil` when the chunk could
    /// not be converted — the session is then done. Runs on `resampleQueue`.
    private func convertChunk(
        session: EnhancedResampleSession,
        inputBuffer: AVAudioPCMBuffer
    ) -> AVAudioPCMBuffer? {
        do {
            let chunk = try session.resampler.convert(inputBuffer, inputEnded: session.reachedEnd)
            if chunk.endOfStream {
                session.reachedEnd = true
            }
            return chunk.buffer
        } catch {
            NSLog("[AudioEngineBridge] resampler convert error: \(error); ending stream")
            session.reachedEnd = true
            return nil
        }
    }
}
