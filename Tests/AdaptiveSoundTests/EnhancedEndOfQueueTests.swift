@testable import AdaptiveSound
import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - The end of the queue plays the last track to its last frame (R1.1-A close-out, S-1)

//
// When the queue runs out, the view model stops the engine at the next tick after the end flag. So
// the flag must not rise before the player has played the final track's last frame. On the
// resampler sub-path it rose as soon as the reader had scheduled the flush: 68–199 ms of the track
// still queued, cut by that stop (fade-outs, reverb tails) — and a track shorter than ~0.4 s after a
// same-rate join lost almost everything, its end raised at the join itself. The real bridge plays
// on an offline engine (`EnhancedTransportRig`), paced at a device's speed; the player's own frame
// count says how far it had played when the flag rose, and a tap on the player records what it
// played. A user's stop or seek must still cut at once.

@Suite("Enhanced end of queue — the last frame plays before the end (S-1)", .serialized, .timeLimit(.minutes(5)))
struct EnhancedEndOfQueueTests {
    typealias Rig = EnhancedTransportRig

    static let tones: [Double] = [60, 3000]
    static let chunk = Int(StreamingResampler.inputChunkFrames)

    /// One case: the final track's sub-path and length, and the track it follows through a same-rate
    /// join (`nil`: it plays alone).
    struct Case: Sendable, CustomTestStringConvertible {
        let rate: Double
        let frames: Int
        let after: Int?

        var testDescription: String {
            let alone = after.map { "after a \($0)-frame track through a join" } ?? "alone"
            return "\(Int(rate)) Hz, \(frames) frames, \(alone)"
        }
    }

    static let cases: [Case] = [
        // The resampler: the track ends 64, 4096 and 8100 frames into its last chunk.
        Case(rate: 44100, frames: chunk * 8 + 64, after: nil),
        Case(rate: 44100, frames: chunk * 8 + 4096, after: nil),
        Case(rate: 44100, frames: chunk * 8 + 8100, after: nil),
        Case(rate: 96000, frames: chunk * 12 + 3000, after: nil),
        // The resampler, after a same-rate join: a whole track, one of 0.3 s, one of 1000 frames.
        Case(rate: 44100, frames: chunk * 6, after: chunk * 8 + 4096),
        Case(rate: 44100, frames: 13230, after: chunk * 8 + 4096),
        Case(rate: 44100, frames: 1000, after: chunk * 8 + 4096),
        // The passthrough sub-path (the graph's rate): its file plays straight onto the player.
        Case(rate: 48000, frames: 48000 + 777, after: nil),
    ]

    @Test("the end of the queue rises only after the final track's last frame has played", arguments: cases)
    func lastFramePlaysBeforeTheEnd(_ test: Case) async throws {
        let rig = try await Self.play(test, name: "end-of-queue")
        let bridge = rig.bridge
        let recording = try rig.recordPlayer()
        let program = try Self.program(test)
        let seams = test.after == nil ? 0 : 1

        let endAt = try #require(await rig.frames(until: { bridge.gaplessPlaybackEnded }, limit: program.count + 48000),
                                 "the end never rose")
        let played = try Self.playerFrames(bridge)
        print("[end] \(test.testDescription): the end rose with \(played) of \(program.count) frames played "
            + "(\(String(format: "%.0f", Double(played - program.count) / 48)) ms after the last; checked at \(endAt))")
        #expect(played >= program.count, "the end rose \(program.count - played) frames before the track's last frame")
        #expect(bridge.gaplessTransitionCount == UInt64(seams), "the seam counted, and before the end")

        // Everything the program holds reached the player, exactly.
        _ = try await rig.samples(frames: 9600) // the tap hands its frames over in whole buffers
        let heard = try await recording.samples(frames: program.count)
        let error = zip(heard, program).reduce(Float(0)) { max($0, abs($1.0 - $1.1)) }
        #expect(error <= 1e-5, "what the player played differs from the program by \(error)")
        await rig.finish()
    }

    // MARK: A user's stop or seek still cuts at once

    @Test("a stop in the track's last moments stops at once, and raises no end", arguments: [44100.0, 48000.0])
    func stopNearTheEndCutsAtOnce(rate: Double) async throws {
        let frames = rate == Rig.graphRate ? 48000 : Self.chunk * 8 + 4096
        let rig = try await Self.play(Case(rate: rate, frames: frames, after: nil), name: "end-stop")
        let bridge = rig.bridge
        let total = Int((Double(frames) * Rig.graphRate / rate).rounded(.up))
        _ = try #require(await rig.samples(frames: total - 4800)) // 100 ms before its last frame
        try await bridge.stopAudio(epoch: 1, pausing: false)
        let player = try #require(bridge.playerNodeRef)
        #expect(!player.isPlaying, "the stop stops the player at once")
        // The completions the stop set off (AVFAudio fires them for the buffers it drops) have been handed on
        // and their work has run: the positive witness that a stop's end WOULD have risen by now.
        try await rig.untilSupersededCompletionsLand()
        #expect(!bridge.gaplessPlaybackEnded, "a stopped track never reports an end")
        await rig.finish()
    }

    @Test("a seek after the whole stream is scheduled plays from its place, and the old stream's end never rises")
    func seekAfterTheStreamIsScheduled() async throws {
        let frames = Self.chunk * 8 + 4096
        let rig = try await Self.play(Case(rate: 44100, frames: frames, after: nil), name: "end-seek")
        let bridge = rig.bridge
        let streamFinished = { bridge.resampleQueue.sync { bridge.resampleSession?.reachedEnd ?? false } }
        let scheduled = try await rig.frames(until: streamFinished, limit: 96000)
        try #require(scheduled != nil, "the stream never finished scheduling")
        let (error, _) = await rig.seek(to: 0.25)
        #expect(error == nil)
        let after = try #require(await rig.render(seconds: 0.4))
        #expect(after > 0.01, "the track plays on from its new place")
        #expect(!bridge.gaplessPlaybackEnded, "the replaced stream's end never rises")
        let position = try #require(rig.position)
        #expect(abs(position - 0.65) < 0.02, "the playhead is the seek's: \(position)")
        await rig.finish()
    }

    // MARK: - Helpers

    /// Play the case: its track alone, or after a track it continues through a same-rate join.
    static func play(_ test: Case, name: String) async throws -> Rig {
        guard let before = test.after else {
            return try await Rig(path: test.rate == Rig.graphRate ? .passthrough : .resampler, name: name,
                                 tones: tones, frames: test.frames, rate: test.rate)
        }
        return try await Rig.playing(tones, rate: test.rate, frames: before, thenNext: test.frames, name: name)
    }

    /// What the player plays for the case, from its first frame: the program itself at the graph's
    /// rate, else one conversion of it (a join included — it is one stream).
    static func program(_ test: Case) throws -> [Float] {
        let frames = (test.after ?? 0) + test.frames
        guard test.rate != Rig.graphRate else {
            return (0 ..< frames).map { Rig.toneSample(tones, frame: $0, rate: test.rate) }
        }
        return try Rig.oneConversion(tones, rate: test.rate, frames: frames)
    }

    /// How many frames the player has played (its own clock: frame j renders in the j-th output frame).
    static func playerFrames(_ bridge: AudioEngineBridge) throws -> Int {
        let player = try #require(bridge.playerNodeRef)
        let renderTime = try #require(player.lastRenderTime)
        let playerTime = try #require(player.playerTime(forNodeTime: renderTime))
        return Int(playerTime.sampleTime)
    }
}
