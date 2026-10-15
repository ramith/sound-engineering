import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge Enhanced resampler — read → convert → schedule iteration

/// The per-iteration read → convert → schedule machinery of the Enhanced streaming resampler.
/// Everything here runs on `resampleQueue` (the prime loop drives it — from `commitEnhanced`'s
/// `resampleQueue.sync`, or a seam handler already on the queue; each `.dataConsumed` completion
/// re-dispatches the next iteration onto `resampleQueue`). The cancellation predicate (`isCurrent`)
/// and the `resampleGeneration` / `resampleSession` reads it performs are confined to
/// `resampleQueue`. The conversion itself is `StreamingResampler`'s (AudioFormatKit), which the
/// `make gate` SRC check drives in the same chunks.
extension AudioEngineBridge {
    // MARK: - Cancellation predicate

    /// Returns `true` when `generation` still matches the live epoch AND `session` is still the
    /// active session — i.e. no seek / stop / track-change has superseded this iteration.
    ///
    /// Must be called on `resampleQueue` (where `resampleGeneration` and `resampleSession` are
    /// exclusively mutated). The predicate is intentionally a simple inline read so the check occurs
    /// at the exact point of the `guard` call-site — no defer, no async, no re-ordering.
    func isCurrent(generation: UInt64, session: EnhancedResampleSession) -> Bool {
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
            // resampleQueue, where all session state is serialized. A join the player has not
            // reached yet goes first: the end waits for it (`commitJoin`).
            if session.pendingJoin != nil {
                session.endAwaitsJoin = true
            } else {
                fireResamplerEOFOrEnd(session: session, player: player)
            }
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

        scheduleConverted(outputBuffer, session: session, player: player, generation: generation)
        return true
    }

    /// Schedule one converted 48 kHz chunk. `.dataConsumed` fires when the player has consumed it; we
    /// then chain the next iteration on the serial queue. The completion does NO converter work
    /// itself — it only re-dispatches — so we never touch the converter off `resampleQueue`.
    ///
    /// The chunk that holds a pending join goes as two buffers: the ending track's frames, whose
    /// completion counts the seam once the player has consumed that track's last frame
    /// (`commitJoin`), then the next track's, which chains. A join at the chunk's end — or past the
    /// stream's last frame — counts on the chunk's own completion. MUST run on `resampleQueue`.
    private func scheduleConverted(
        _ buffer: AVAudioPCMBuffer,
        session: EnhancedResampleSession,
        player: AVAudioPlayerNode,
        generation: UInt64
    ) {
        let chain: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void = { [weak self, weak player] _ in
            guard let self, let player else { return }
            self.resampleQueue.async {
                _ = self.readConvertSchedule(session: session, player: player, generation: generation)
            }
        }
        // This chunk's place in the session's output: it ends where the converter's output stands.
        let chunkEnd = session.resampler.outputFrames
        let chunkStart = chunkEnd - Int64(buffer.frameLength)
        guard let join = session.pendingJoin, join.outputFrame <= chunkEnd || session.reachedEnd else {
            player.scheduleBuffer(buffer, completionCallbackType: .dataConsumed, completionHandler: chain)
            return
        }
        let commit: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void = { [weak self, weak player] _ in
            guard let self, let player else { return }
            self.resampleQueue.async {
                self.commitJoin(session: session, player: player, generation: generation)
            }
        }
        // The ending track's frames in this chunk: never none, as the converter's output trails its
        // input — a join read in one chunk lands in that chunk's output or a later one's.
        let endingFrames = join.outputFrame - chunkStart
        if endingFrames > 0, endingFrames < Int64(buffer.frameLength),
           let ending = buffer.copy(frames: 0 ..< AVAudioFrameCount(endingFrames)),
           let next = buffer.copy(frames: AVAudioFrameCount(endingFrames) ..< buffer.frameLength) {
            player.scheduleBuffer(ending, completionCallbackType: .dataConsumed, completionHandler: commit)
            player.scheduleBuffer(next, completionCallbackType: .dataConsumed, completionHandler: chain)
            return
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { type in
            commit(type)
            chain(type)
        }
    }

    /// Allocate + fill one input chunk from the file. Once the track has run out (its read head at
    /// its length), a next track of the same format fills the chunk instead
    /// (`continueStreamIntoNextTrack`). A read error or an empty chunk marks the session done (so the
    /// next convert flushes the resampler tail). Returns `nil` only if the input buffer could not be
    /// allocated. Runs on `resampleQueue`.
    private func readChunk(session: EnhancedResampleSession) -> AVAudioPCMBuffer? {
        let frames = StreamingResampler.inputChunkFrames
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: session.resampler.inputFormat, frameCapacity: frames
        ) else {
            return nil
        }
        do {
            if session.audioFile.framePosition >= session.audioFile.length {
                continueStreamIntoNextTrack(session: session, filling: inputBuffer)
            } else {
                try session.audioFile.read(into: inputBuffer, frameCount: frames)
            }
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

// MARK: - Frames of a PCM buffer

extension AVAudioPCMBuffer {
    /// A copy of frames `range` of this buffer — float, one buffer per channel, as every file's
    /// processing format and the player's format are (`nil`: another layout, or no memory).
    func copy(frames range: Range<AVAudioFrameCount>) -> AVAudioPCMBuffer? {
        guard range.upperBound <= frameLength, !format.isInterleaved, let source = floatChannelData,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(range.count)),
              let destination = copy.floatChannelData else { return nil }
        for channel in 0 ..< Int(format.channelCount) {
            destination[channel].update(from: source[channel] + Int(range.lowerBound), count: range.count)
        }
        copy.frameLength = AVAudioFrameCount(range.count)
        return copy
    }
}
