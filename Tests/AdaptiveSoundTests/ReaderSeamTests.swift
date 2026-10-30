@testable import AdaptiveSound
@preconcurrency import AVFoundation
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - Short-read files at a gapless seam: one stream, and an end on the last frame (R1.1-B fix round, F1)

//
// E-AC-3, AC-3, ffmpeg-made MP3 and Vorbis deliver fewer frames than `AVAudioFile.length` states (288 fewer on AC-3),
// then fail the read. Two things went wrong with them at a seam:
// - MEDIUM-3: a 48 kHz one scheduled on the player as a file completed when the player's read-ahead met that failure,
//   about a second before its last frame was heard — so the end flag (and with it the view model's stop at the end
//   of the queue, or the next seam's title and plan) came a second early.
// - LOW-6: through the resampler, the reader joined the next song only once the file's position reached `length`,
//   which a short read never does: the next song rolled in with a converter of its own instead of continuing the one
//   stream.
// The REAL bridge plays them on an offline device (`MultichannelDeviceRig`), the render in lock-step with the
// completion chain; nothing is heard.

@Suite("The bridge's reader at a seam: short-read files join in one stream and end on their last frame",
       .serialized, .timeLimit(.minutes(5)), .attachingLogTail)
struct ReaderSeamTests {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    /// One tone in two 1 s halves, 44.1 kHz stereo AC-3: each delivers 44 256 of its 44 544 frames
    /// (Tests/Fixtures/reader/README.md).
    static let part1 = fixtures.appendingPathComponent("reader/tone-ac3-stereo-44k-part1.m4a")
    static let part2 = fixtures.appendingPathComponent("reader/tone-ac3-stereo-44k-part2.m4a")
    /// The break-it's 48 kHz mono AC-3 tone: 96 480 of its 96 768 frames delivered (2.010 of 2.016 s).
    static let shortRead48k = fixtures.appendingPathComponent("breakit-sound/tone-ac3-mono-48k.m4a")
    /// Frames each half's decoder delivers.
    static let partFrames = 44256

    @Test("LOW-6: a 44.1 kHz track whose decoder reads short joins the next in ONE stream, and ends on its last frame")
    func shortReadJoinsInOneStream() async throws {
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        try await rig.play(Self.part1)
        let bridge = rig.bridge
        let stream = try await blocking("the session") { bridge.resampleQueue.sync { bridge.resampleSession } }
        let first = try #require(stream, "a 44.1 kHz file streams through the reader")
        await bridge.setNextTrack(Self.part2, ticket: OnDeckTicket(session: 0, sequence: 1), leveling: .off)

        let seconds = 2 * Double(Self.partFrames) / 44100 // what the two halves deliver: 2.007 s
        var rendered = 0.0
        var seamAt: Double?
        var endedAt: Double?
        var sameStreamAtSeam = false
        while rendered < seconds + 0.5 {
            _ = try await rig.render(frames: 2400)
            rendered += 0.05
            if seamAt == nil, bridge.gaplessTransitionCount == 1 {
                seamAt = rendered
                let now = try await blocking("the session") { bridge.resampleQueue.sync { bridge.resampleSession } }
                sameStreamAtSeam = now === first
            }
            if endedAt == nil, bridge.gaplessPlaybackEnded {
                endedAt = rendered
            }
        }
        await rig.finish()
        let seam = try #require(seamAt, "the seam into the second half was never counted")
        let ended = try #require(endedAt, "the stream never ended")
        // One stream: the second half continued the first's session (and its converter), as a same-format seam of
        // files that read in full does — not a roll into a converter of its own.
        #expect(sameStreamAtSeam, "the second half rolled into a new session instead of continuing the stream")
        // The seam lands where the first half's delivered frames end (1.0035 s), counted when the player consumed
        // them; the end where the second half's do — not before.
        let firstEnds = Double(Self.partFrames) / 44100
        #expect(abs(seam - firstEnds) <= 0.1, "the seam counted at \(seam) s; the first half ends at \(firstEnds) s")
        #expect(ended >= seconds - 0.05, "the end came at \(ended) s; the two halves play until \(seconds) s")
    }

    /// Song A streams through the resampler (44.1 kHz), so the roll into B lands while A's last buffers are still
    /// queued, as a device's would. A song A that plays straight through (48 kHz PCM) is not used here: its roll
    /// waits for the player's completion of a FILE schedule, which can come once the player has run dry — the next
    /// song then starts one render lead late (KI-GAP-01; measured in this rig under load: ~8 200 frames, on the
    /// converter path as on the reader's), and a lock-step render, which counts on contiguous schedules, cannot
    /// follow a gap. The refusal test below covers that roll's other branch.
    @Test("MEDIUM-3: a seam into a 48 kHz AC-3 track ends it on its last frame, not ~1 s early")
    func seamIntoShortRead48kEndsOnTime() async throws {
        // B is the 48 kHz AC-3 tone. Both mono, so the seam keeps the graph's width.
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        let mono = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Mono))
        let songA = try MultichannelFixture.write(layout: mono, rate: 44100, name: "reader-seam-a")
        defer { try? FileManager.default.removeItem(at: songA) }
        try await rig.play(songA)
        let bridge = rig.bridge
        await bridge.setNextTrack(Self.shortRead48k, ticket: OnDeckTicket(session: 0, sequence: 1), leveling: .off)

        let lengthA = MultichannelFixture.seconds
        // B's decodable length, as this macOS's decoder gives it (2.010 s of the stated 2.016 s on macOS 26).
        let delivered = try Double(TrackReaderTests.framesDecoded(at: Self.shortRead48k)) / 48000
        var rendered = 0.0
        var seamAt: Double?
        var endedAt: Double?
        var lastSound = 0.0
        while rendered < lengthA + delivered + 1 {
            let block = try await rig.render(frames: 2400)
            if let loud = block[0].lastIndex(where: { abs($0) > 1e-3 }) {
                lastSound = rendered + Double(loud) / MultichannelDeviceRig.graphRate
            }
            rendered += 0.05
            if seamAt == nil, bridge.gaplessTransitionCount == 1 {
                seamAt = rendered
            }
            if endedAt == nil, bridge.gaplessPlaybackEnded {
                endedAt = rendered
            }
        }
        await rig.finish()
        #expect(seamAt != nil, "the seam into the AC-3 track was never counted")
        let ended = try #require(endedAt, "the AC-3 track never ended")
        // The view model stops at the end of the queue as the flag goes up: it must not rise before the last frame
        // has played. It used to, ~1 s early: the player completed the file when its read-ahead met the decoder's
        // failure past the delivered frames.
        let lastFrame = lengthA + delivered
        #expect(ended >= lastFrame - 0.1,
                "the end came at \(ended) s; B plays until \(lastFrame) s (its tone sounded to \(lastSound) s)")
    }

    /// A seam into a file Apple's decoder refuses: (song A's rate, when B is armed — at once, or once A's reader
    /// has passed its end).
    static let refusals: [(rateA: Double, armAt: Double)] = [(48000, 0), (44100, 0), (44100, 0.6)]

    @Test("KI-PB-22 / LOW-4: a seam into a file the decoder refuses — the song before plays out, then the end",
          arguments: refusals)
    func seamIntoARefusedFileEndsTheSongBefore(rateA: Double, armAt: Double) async throws {
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        let mono = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Mono))
        let songA = try MultichannelFixture.write(layout: mono, rate: rateA, name: "reader-refused-a")
        let broken = try BreakItTinyFlac.write(named: "reader-refused-b", rate: 48000, blockSize: 128)
        defer {
            try? FileManager.default.removeItem(at: songA)
            try? FileManager.default.removeItem(at: broken)
        }
        try await rig.play(songA)
        let bridge = rig.bridge
        let lengthA = MultichannelFixture.seconds
        var rendered = 0.0
        var armed = false
        var endedAt: Double?
        var lastSound = 0.0
        while rendered < lengthA + 1 {
            if !armed, rendered >= armAt {
                await bridge.setNextTrack(broken, ticket: OnDeckTicket(session: 0, sequence: 1), leveling: .off)
                armed = true
            }
            let block = try await rig.render(frames: 2400)
            if let loud = block[0].lastIndex(where: { abs($0) > 1e-3 }) {
                lastSound = rendered + Double(loud) / MultichannelDeviceRig.graphRate
            }
            rendered += 0.05
            if endedAt == nil, bridge.gaplessPlaybackEnded {
                endedAt = rendered
            }
        }
        await rig.finish()
        #expect(bridge.gaplessTransitionCount == 0, "a seam was counted into a file that can't play")
        let ended = try #require(endedAt, "the playback never ended: the view model would poll a silent engine")
        #expect(ended >= lengthA - 0.05 && ended <= lengthA + 0.3,
                "the end came at \(ended) s; song A plays until \(lengthA) s (its tone sounded to \(lastSound) s)")
        #expect(lastSound >= lengthA - 0.05, "song A was cut at \(lastSound) s of \(lengthA) s")
    }
}
