@testable import AdaptiveSound
import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - A same-rate gapless seam plays as one conversion (council C-22, P3 D39 b–d, D40; KI-GAP-04)

//
// Two 44.1 kHz tracks cut from one continuous sound, joined gaplessly on the 48 kHz graph, must play
// exactly as ONE conversion of the joined input would: no click, no inserted silence, no frame lost
// or added. The real bridge plays them on an offline engine (`EnhancedTransportRig`), the render
// paced at a device's speed (the seam's timing comes from the player's completion chain); a tap on
// the player records what the bridge scheduled, before the effects chain, and the oracle is the
// production `StreamingResampler` run once over the joined input.
//
// Before this fix every track had its own converter: each side of the join was converted as if
// bordered by silence (a click up to 17 dB below the peak, ±240 frames wide with Mastering), B came
// one frame early whenever A's converted length was not a whole number of frames, and B's converter
// started only once A's last chunk had been scheduled — the race the P3 panel measured as a 279-frame
// gap. The seam's count, title, playhead and loudness gain all moved when A's decode ended, up to a
// chunk before B was heard (D40).

@Suite(
    "Enhanced gapless — one converter across a same-rate seam (C-22, KI-GAP-04)",
    .serialized, .timeLimit(.minutes(5))
)
struct EnhancedSeamTests {
    typealias Rig = EnhancedTransportRig

    /// The council's seam signal (P3 D39 c): 60 Hz + 3 kHz.
    static let tones: [Double] = [60, 3000]
    /// Both tracks' rate: a CD album's.
    static let rate = 44100.0
    static let chunk = Int(StreamingResampler.inputChunkFrames)
    /// Track B: six chunks (1.1 s).
    static let nextFrames = chunk * 6
    /// Track A ends 64, 4096 and 8100 frames into its last chunk (the panel's three cases: at 64,
    /// a converter per track left 279 frames of silence at the join in its replica).
    static let lengths = [chunk * 8 + 64, chunk * 8 + 4096, chunk * 8 + 8100]
    /// The largest difference from one continuous conversion allowed anywhere in the program.
    static let tolerance: Float = 1e-5

    // MARK: The join

    @Test("two 44.1 kHz tracks joined on the 48 kHz graph are ONE conversion: no click, no gap, no frame lost",
          arguments: lengths)
    func sameRateSeamIsOneConversion(lengthA: Int) async throws {
        let rig = try await Self.playWithNextOnDeck(lengthA: lengthA, name: "seam-join")
        let recording = try rig.recordPlayer()
        let reference = try Self.continuousConversion(frames: lengthA + Self.nextFrames)
        let total = reference.count + 4800
        _ = try #require(await rig.samples(frames: total + 9600))
        let played = try await recording.samples(frames: total)
        let seam = Self.seamFrame(lengthA)

        // Where B's sound lands against the one conversion (measured past the join, where a per-track
        // converter's transient has died away), and the error at and around the join.
        let inserted = Self.alignment(played, reference, at: seam + 2000).frames
        let join = Self.peakError(played, reference, over: (seam - 2000) ..< (seam + 2000))
        let click = Self.peakError(played, reference, shiftedBy: inserted, over: (seam - 2000) ..< (seam + 2000))
        let everywhere = Self.peakError(played, reference, over: 0 ..< reference.count)
        let after = played[reference.count...].reduce(Float(0)) { max($0, abs($1)) }
        let peak = Rig.toneAmplitude
        print("[seam] A = \(lengthA) frames (ends \(lengthA % Self.chunk) into its last chunk): inserted \(inserted) "
            + "frames; join error \(join) (\(Self.decibels(join, re: peak)) dB re peak), \(click) "
            + "(\(Self.decibels(click, re: peak)) dB) with B realigned; whole program \(everywhere); after \(after)")

        #expect(inserted == 0, "B's sound lands \(inserted) frames late (negative: early)")
        #expect(join <= Self.tolerance, "join error \(join) (\(Self.decibels(join, re: peak)) dB re peak)")
        #expect(everywhere <= Self.tolerance, "the program differs from one conversion by \(everywhere)")
        #expect(after == 0, "nothing plays after the joined program's last frame")
        #expect(rig.bridge.gaplessTransitionCount == 1, "one seam")
        await rig.finish()
    }

    // MARK: The frame accounting

    @Test("the seam lands on its frame: not counted while A plays, then the count, the file and the playhead exact")
    func seamLandsOnItsFrame() async throws {
        let lengthA = Self.chunk * 8 + 4096
        let rig = try await Self.playWithNextOnDeck(lengthA: lengthA, name: "seam-frame")
        let bridge = rig.bridge
        let seam = Self.seamFrame(lengthA)
        let durationA = Double(lengthA) / Self.rate

        // Everything up to A's last output frame, but not that frame: A is still what plays.
        _ = try #require(await rig.samples(frames: seam - 1))
        Self.drain(bridge) // the render already waited for every completion due; this runs what they queued
        #expect(bridge.gaplessTransitionCount == 0, "the seam was counted before B was heard (D40)")
        #expect(bridge.lastFileURL == rig.url, "A is still the playing file")
        let beforeSeam = try #require(rig.position)
        #expect(beforeSeam <= durationA, "the playhead is still inside A: \(beforeSeam) of \(durationA)")

        // A's last frame, and one block of B: the seam is counted once the player has consumed A.
        _ = try #require(await rig.samples(frames: 1 + 512))
        try await until("the seam to be counted") { bridge.gaplessTransitionCount == 1 }
        #expect(bridge.lastFileURL != rig.url, "B is the playing file")

        // The playhead is the player's time less A's whole length: B's time from its own first frame,
        // exactly — not re-zeroed at whatever moment the seam happened to run.
        let player = try #require(bridge.playerNodeRef)
        let renderTime = try #require(player.lastRenderTime)
        let playerTime = try #require(player.playerTime(forNodeTime: renderTime))
        let position = try #require(rig.position)
        let expected = Double(playerTime.sampleTime) / playerTime.sampleRate - durationA
        #expect(abs(position - expected) < 1e-9, "playhead \(position) s, B's time is \(expected) s")
        await rig.finish()
    }

    @Test("a next track shorter than a chunk: one conversion, and the seam counted before the end")
    func shortNextTrackSeamsBeforeItEnds() async throws {
        let lengthA = Self.chunk * 8 + 4096
        let lengthB = 1000
        let rig = try await Self.playWithNextOnDeck(lengthA: lengthA, nextFrames: lengthB, name: "seam-short")
        let bridge = rig.bridge
        let recording = try rig.recordPlayer()
        let reference = try Self.continuousConversion(frames: lengthA + lengthB)
        _ = try #require(await rig.samples(frames: reference.count + 4800 + 9600))
        try await until("the end of the program to be flagged") { bridge.gaplessPlaybackEnded }
        #expect(bridge.gaplessTransitionCount == 1, "the seam is counted, and before the end")
        let played = try await recording.samples(frames: reference.count + 4800)
        let error = Self.peakError(played, reference, over: 0 ..< reference.count)
        #expect(error <= Self.tolerance, "the program differs from one conversion by \(error)")
        await rig.finish()
    }

    // MARK: A seek before the join is heard

    @Test("a seek before the taken join is heard: a fresh converter, the next track back on deck, one conversion again")
    func seekBeforeTheJoinIsHeard() async throws {
        let lengthA = Self.chunk * 8 + 4096
        let rig = try await Self.playWithNextOnDeck(lengthA: lengthA, name: "seam-seek")
        let bridge = rig.bridge
        let recording = try rig.recordPlayer()

        // Play until the stream has taken B (its join pending), short of hearing it.
        var rendered = 0
        while bridge.resampleQueue.sync(execute: { bridge.resampleSession?.pendingJoin == nil }) {
            _ = try #require(await rig.samples(frames: 512))
            rendered += 512
            try #require(rendered < Self.seamFrame(lengthA), "the stream never took the next track")
        }
        let lead = Double(Self.seamFrame(lengthA) - rendered) / Rig.graphRate
        print("[seam] the stream took the next track \(String(format: "%.0f", lead * 1000)) ms before the join")
        let taken = try #require(bridge.resampleQueue.sync { bridge.resampleSession })
        let (error, _) = await rig.seek(to: 0.5)
        #expect(error == nil)
        let state = bridge.resampleQueue.sync {
            (session: bridge.resampleSession, deck: bridge.onDeckURL, hook: bridge.onResamplerEOF != nil)
        }
        #expect(state.session !== taken, "the seek starts a fresh converter")
        #expect(state.session?.pendingJoin == nil)
        #expect(state.deck != nil, "the next track is back on deck")
        #expect(state.hook, "with its hook")
        #expect(bridge.gaplessTransitionCount == 0, "no seam yet")
        #expect(bridge.lastFileURL == rig.url, "A plays on")

        // From the seek's frame, A then B are again one conversion.
        let from = Int((0.5 * Self.rate).rounded())
        let reference = try Self.continuousConversion(frames: lengthA + Self.nextFrames - from, from: from)
        _ = try #require(await rig.samples(frames: reference.count + 4800 + 9600))
        try await until("the seam to be counted") { bridge.gaplessTransitionCount == 1 }
        let played = try await recording.samples(frames: rendered + reference.count + 4800)
        let afterSeek = Array(played[rendered...])
        let joined = Self.peakError(afterSeek, reference, over: 0 ..< reference.count)
        #expect(joined <= Self.tolerance, "after the seek the program differs from one conversion by \(joined)")
        await rig.finish()
    }

    // MARK: A join that changes the format keeps its own converter

    @Test("a join to another rate or channel count starts a fresh converter, as before",
          arguments: [(rate: 96000.0, channels: AVAudioChannelCount(2)), (rate: 44100.0, channels: 1)])
    func formatChangingSeamStartsAFreshConverter(next: (rate: Double, channels: AVAudioChannelCount)) async throws {
        let lengthA = Self.chunk * 8 + 4096
        let rig = try await Rig(path: .resampler, name: "seam-format", tones: Self.tones, frames: lengthA)
        let bridge = rig.bridge
        let nextURL = try rig.writeTrack([1000], named: "seam-format-next", rate: next.rate,
                                         frames: 0 ..< Int(next.rate), channels: next.channels)
        await bridge.setNextTrack(nextURL, ticket: OnDeckTicket(session: 0, sequence: 1))
        let first = try #require(bridge.resampleQueue.sync { bridge.resampleSession })

        let output = try #require(await rig.samples(frames: Self.seamFrame(lengthA) + 24000))
        try await until("the seam to be counted") { bridge.gaplessTransitionCount == 1 }
        let second = try #require(bridge.resampleQueue.sync { bridge.resampleSession })
        #expect(second !== first, "the next track has its own converter")
        #expect(second.resampler.inputFormat.sampleRate == next.rate)
        #expect(second.resampler.inputFormat.channelCount == next.channels)
        let heard = output[(output.count - 9600)...].reduce(Float(0)) { max($0, abs($1)) }
        #expect(heard > 0.01, "the next track plays")
        await rig.finish()
    }

    // MARK: - Helpers

    /// Play track A (`lengthA` frames of the program) through the real bridge, with track B — the
    /// program's next `nextFrames`, so the two join into one sound — on deck.
    static func playWithNextOnDeck(lengthA: Int, nextFrames: Int = nextFrames, name: String) async throws -> Rig {
        try await Rig.playing(tones, rate: rate, frames: lengthA, thenNext: nextFrames, name: name)
    }

    /// The first output frame of the track that starts at input frame `inputFrame`: the converter
    /// lines its output up with the input's time, so the first 48 kHz frame at or after it.
    static func seamFrame(_ inputFrame: Int) -> Int {
        Int((Double(inputFrame) * Rig.graphRate / rate).rounded(.up))
    }

    /// ONE conversion of `frames` frames of the program from frame `from` (`Rig.oneConversion`).
    static func continuousConversion(frames: Int, from first: Int = 0) throws -> [Float] {
        try Rig.oneConversion(tones, rate: rate, frames: frames, from: first)
    }

    /// The shift (frames; negative: early) that best lines `output` up with `reference` over 400
    /// frames from `start`, and the peak error left there.
    static func alignment(_ output: [Float], _ reference: [Float], at start: Int) -> (frames: Int, error: Float) {
        let probe = start ..< start + 400
        var best = (frames: 0, error: Float.infinity)
        for shift in -50 ..< 2500 where probe.upperBound + shift <= output.count {
            let error = peakError(output, reference, shiftedBy: shift, over: probe)
            if error < best.error {
                best = (shift, error)
            }
        }
        return best
    }

    /// The largest |output − reference| over `range` of the reference, with `output` read `shift`
    /// frames later.
    static func peakError(_ output: [Float], _ reference: [Float], shiftedBy shift: Int = 0,
                          over range: Range<Int>) -> Float {
        range.reduce(Float(0)) { max($0, abs(output[$1 + shift] - reference[$1])) }
    }

    static func decibels(_ value: Float, re peak: Float) -> String {
        String(format: "%.1f", 20 * log10(Double(max(value, 1e-12)) / Double(peak)))
    }

    /// Run what the delivered completions queued on `resampleQueue`.
    static func drain(_ bridge: AudioEngineBridge) {
        bridge.resampleQueue.sync {}
    }
}
