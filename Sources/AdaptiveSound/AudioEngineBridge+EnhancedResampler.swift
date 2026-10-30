import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge Enhanced streaming-resampler path

/// The bridge's own reader: the Enhanced path for a file whose rate is not the graph's 48 kHz, and for a 48 kHz
/// file whose decoder may deliver fewer frames than its length states (`playsStraightThrough`: a lossy codec).
/// The file is read in chunks by Apple's decoder (`TrackFileReader`, its place counted), converted — by
/// `StreamingResampler` (Apple's Mastering-quality converter, configured once in AudioFormatKit — the code
/// `make gate`'s SRC check measures) when the rate differs, by nothing when the file is already in the player's
/// format (`StraightThrough`: a 48 kHz file is never resampled) — and scheduled on the player. The stream ends on
/// the frames the decoder delivered. A file that plays straight through never comes here (the player reads it).
/// Starts, seeks and re-establishes reach it through the one Enhanced restart (`commitEnhanced`,
/// AudioEngineBridge+EnhancedRestart); the gapless seams through `primeEnhancedResamplerLocked`.
///
/// Design:
/// - One `EnhancedResampleSession` per stream: each start, seek, re-establish and format-changing
///   seam makes a new one — the file's reader and its conversion, file format →
///   `player.outputFormat(forBus: 0)` (48 kHz float in the file's own layout, F1: the rate changes, never
///   a channel's slot), so `scheduleBuffer` needs no further conversion. A SAME-format seam keeps it: the next
///   file's frames continue the stream through the same conversion (`continueStreamIntoNextTrack`,
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
    /// `dispatchPrecondition`. Bumps the generation, installs the session, places its reader (a fresh
    /// session reads from the top; a restart from its place), and schedules up to `resamplePrimeCount`
    /// initial buffers. Does not play: the caller starts the player (a restart), or it is already running
    /// (a gapless seam).
    ///
    /// Returns the number of buffers scheduled (0: nothing could be read or converted from
    /// `startFrame`, or the decoder could not seek there — the caller ends the track or falls back).
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

        // Bump the generation so any prior session's in-flight iterations abandon themselves,
        // then capture THIS session's generation for the loop to compare against.
        resampleGeneration &+= 1
        let generation = resampleGeneration
        resampleSession = session

        // Place the reader through its own count — never the file's place (KI-PB-22).
        if startFrame != session.reader.position {
            do {
                try session.reader.seek(to: startFrame)
            } catch {
                logUX("resampler: the decoder could not seek to frame \(startFrame) — \(error)")
                return 0
            }
        }

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
        supersedeObservedSchedule() // before the stop: the completions it fires are not owed
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

/// One stream through the bridge's own reader: the file's reader and its conversion — and, past a same-format seam,
/// the next file through the same conversion. A class (reference type) so the completion-chained iterations share
/// one instance; held by the bridge as `resampleSession` and only ever mutated on `resampleQueue`.
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
        /// Its first frame in the session's output (`StreamConversion.outputFrame(atInputFrame:)`).
        let outputFrame: Int64
        /// The length of the track that ends there, in seconds (its frames over its rate, as the view
        /// model reads a duration): the playhead's base moves back by exactly this.
        let endingTrackSeconds: Double
    }

    /// The conversion: file format → the player's format. For the track a start or restart opens, the player's
    /// format is that file's own layout at the graph's rate (`engineFormat`, F1), so it converts the rate only —
    /// or, for a file already in it, nothing (`StraightThrough`); a seam to a track in another layout (KI-GAP-05)
    /// is re-laid into the playing one by label.
    let resampler: any StreamConversion

    /// The source's reader, read sequentially chunk-by-chunk, its place counted: the session's track, then each
    /// next track the stream continues into (`continueStream`).
    private(set) var reader: TrackFileReader

    /// Set once the file is exhausted / the converter signals end — stops further chaining.
    var reachedEnd: Bool = false

    /// The join the player has yet to reach (one at a time); `nil` once it is counted.
    private(set) var pendingJoin: Join?

    /// A next track found to need its own converter (another format): not opened again for a join.
    var refusedJoin: URL?

    /// `nil` when Apple's decoder can't read `file` or Apple has no converter from its processing format to
    /// `outputFormat`.
    init?(file: AVAudioFile, outputFormat: AVAudioFormat) {
        do {
            reader = try TrackFileReader(reading: file)
        } catch {
            NSLog("[AudioEngineBridge] no reader for \(file.url.lastPathComponent): \(error)")
            return nil
        }
        if file.processingFormat == outputFormat {
            resampler = StraightThrough(format: outputFormat)
        } else if let converter = StreamingResampler(from: file.processingFormat, to: outputFormat) {
            resampler = converter
        } else {
            NSLog("[AudioEngineBridge] no converter \(file.processingFormat) -> \(outputFormat)")
            return nil
        }
    }

    /// Go on reading `next` (`url`) once the current track has run out: its first frame follows the
    /// last the conversion has taken. The join is pending until the player reaches it.
    func continueStream(into next: TrackFileReader, url: URL) {
        pendingJoin = Join(
            url: url,
            outputFrame: resampler.outputFrame(atInputFrame: resampler.inputFrames),
            endingTrackSeconds: Double(reader.length) / reader.processingFormat.sampleRate
        )
        reader = next
    }

    /// The pending join, now reached: hand it over, once.
    func takePendingJoin() -> Join? {
        defer { pendingJoin = nil }
        return pendingJoin
    }
}

// MARK: - The stream's conversion

/// How a session's stream reaches the player's format, one chunk at a time, with its frames counted so a join can
/// be placed in the output: Apple's Mastering converter (`StreamingResampler`) when the rate or the layout differs,
/// or nothing at all when the file is already in the player's format (`StraightThrough`).
protocol StreamConversion: AnyObject {
    /// What `convertChunk` takes: the source's format.
    var inputFormat: AVAudioFormat { get }
    /// What it returns: the player's format.
    var outputFormat: AVAudioFormat { get }
    /// Input frames taken since the stream began (every track it carried).
    var inputFrames: Int64 { get }
    /// Output frames returned since the stream began.
    var outputFrames: Int64 { get }
    /// Whether input of `format` can go on through this stream (a same-format join).
    func canContinue(with format: AVAudioFormat) -> Bool
    /// Where input frame `inputFrame` (counted from the stream's start) begins in the output.
    func outputFrame(atInputFrame inputFrame: Int64) -> Int64
    /// Convert one chunk; `inputEnded`: none follows it. `ended`: the stream's last output has been returned.
    func convertChunk(_ input: AVAudioPCMBuffer, inputEnded: Bool) throws -> (buffer: AVAudioPCMBuffer, ended: Bool)
}

extension StreamingResampler: StreamConversion {
    func convertChunk(_ input: AVAudioPCMBuffer, inputEnded: Bool) throws -> (buffer: AVAudioPCMBuffer, ended: Bool) {
        let chunk = try convert(input, inputEnded: inputEnded)
        return (chunk.buffer, chunk.endOfStream)
    }
}

/// The conversion of a stream already in the player's format: none. Each chunk goes to the player as the decoder
/// delivered it, so the output is the decoded file, sample for sample, and its frames are the input's.
final class StraightThrough: StreamConversion {
    let inputFormat: AVAudioFormat
    let outputFormat: AVAudioFormat
    private(set) var inputFrames: Int64 = 0

    var outputFrames: Int64 {
        inputFrames
    }

    init(format: AVAudioFormat) {
        inputFormat = format
        outputFormat = format
    }

    func canContinue(with format: AVAudioFormat) -> Bool {
        format == inputFormat
    }

    func outputFrame(atInputFrame inputFrame: Int64) -> Int64 {
        inputFrame
    }

    func convertChunk(_ input: AVAudioPCMBuffer, inputEnded: Bool) -> (buffer: AVAudioPCMBuffer, ended: Bool) {
        inputFrames += Int64(input.frameLength)
        return (input, inputEnded)
    }
}
