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
/// - One `EnhancedResampleSession` per stream: each start, seek, re-establish and format-changing
///   seam makes a new one — the open file and its converter, file format →
///   `player.outputFormat(forBus: 0)` (48 kHz, N-channel float), so `scheduleBuffer` triggers no
///   further engine conversion. A seam to a track of the SAME format keeps the session: the next
///   file's frames continue the stream through the same converter (`continueStreamIntoNextTrack`,
///   AudioEngineBridge+GaplessRoll), and the seam is counted when the player reaches it.
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
    /// seek). So a next track the stream had already taken for a join the player never reached goes
    /// back on deck (`returningUnheardJoin`; unless a newer pick is there), with its hook: the join
    /// comes round again. Returns the new passthrough epoch, for the schedule that replaces the old
    /// one. MUST be called on `resampleQueue`.
    @discardableResult
    func supersedeEnhancedScheduleLocked(returningUnheardJoin: Bool = true) -> UInt64 {
        dispatchPrecondition(condition: .onQueue(resampleQueue))
        if returningUnheardJoin, let join = resampleSession?.pendingJoin, onDeckURL == nil,
           let player = playerNode {
            onDeckURL = join.url
            armResamplerNextTrack(player: player)
        }
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

    /// The body of `stopEnhancedResampler`, for a caller already on `resampleQueue`. The playback's
    /// seam state ends: a join the player never reached does not go back on deck.
    func stopEnhancedResamplerLocked() {
        supersedeEnhancedScheduleLocked(returningUnheardJoin: false)
        onResamplerEOF = nil
        onPassthroughEOF = nil
    }
}

// MARK: - EnhancedResampleSession

/// One stream through the Enhanced streaming resampler: the open file and its converter — and, past
/// a same-format seam, the next file through the same converter. A class (reference type) so the
/// completion-chained iterations share one instance; held by the bridge as `resampleSession` and
/// only ever mutated on `resampleQueue`.
///
/// `@unchecked Sendable` invariant: this session is created on a bridge queue and *only ever used
/// and mutated on* `resampleQueue` once installed. The completion closures that capture it do
/// nothing but re-dispatch onto `resampleQueue`. Single-serial-queue confinement is the external
/// synchronization that makes `@unchecked` truthful; it is never touched on the render/tap (RT)
/// thread, so no allocation/lock is added there.
final class EnhancedResampleSession: @unchecked Sendable {
    /// A join the stream has passed and the player has not reached yet: where the next track starts.
    struct Join {
        /// The track that starts there.
        let url: URL
        /// Its first frame in the session's output (`StreamingResampler.outputFrame(atInputFrame:)`).
        let outputFrame: Int64
        /// The length of the track that ends there, in seconds (its frames over its rate, as the view
        /// model reads a duration): the playhead's base moves back by exactly this.
        let endingTrackSeconds: Double
    }

    /// The converter: file format → the player's format (the Mastering `StreamingResampler`).
    let resampler: StreamingResampler

    /// The open source file, read sequentially chunk-by-chunk: the session's track, then each next
    /// track the stream continues into (`continueStream`).
    private(set) var audioFile: AVAudioFile

    /// Set once the file is exhausted / the converter signals end — stops further chaining.
    var reachedEnd: Bool = false

    /// The join the player has yet to reach (one at a time); `nil` once it is counted.
    private(set) var pendingJoin: Join?

    /// The stream ended with a join still unheard: its end (`fireResamplerEOFOrEnd`) waits for the
    /// join to be counted, so the view model never sees the end before the seam.
    var endAwaitsJoin = false

    /// A next track found to need its own converter (another format): not opened again for a join.
    var refusedJoin: URL?

    /// `nil` when Apple has no converter from `file`'s processing format to `outputFormat`.
    init?(file: AVAudioFile, outputFormat: AVAudioFormat) {
        guard let resampler = StreamingResampler(from: file.processingFormat, to: outputFormat) else {
            NSLog("[AudioEngineBridge] no converter \(file.processingFormat) -> \(outputFormat)")
            return nil
        }
        self.resampler = resampler
        audioFile = file
    }

    /// Go on reading `next` (`url`) once the current track has run out: its first frame follows the
    /// last the converter has taken. The join is pending until the player reaches it.
    func continueStream(into next: AVAudioFile, url: URL) {
        pendingJoin = Join(
            url: url,
            outputFrame: resampler.outputFrame(atInputFrame: resampler.inputFrames),
            endingTrackSeconds: Double(audioFile.length) / audioFile.processingFormat.sampleRate
        )
        audioFile = next
    }

    /// The pending join, now reached: hand it over, once.
    func takePendingJoin() -> Join? {
        defer { pendingJoin = nil }
        return pendingJoin
    }
}
