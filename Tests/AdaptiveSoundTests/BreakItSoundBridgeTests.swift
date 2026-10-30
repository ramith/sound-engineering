@testable import AdaptiveSound
import AudioDSP
@preconcurrency import AVFoundation
import Foundation
import LevelingKit
import RigKit
import Testing

// MARK: - Break-it, R1.1-B sound half: the real bridge on an offline engine (nothing is heard)

//
// The REAL `AudioEngineBridge` and its two AUs on an offline stereo device (lane 2's `MultichannelDeviceRig`): a file
// starts through the bridge's own start (`playFile`), the render is pulled in lock-step with the completion chain, and
// what is read — the end flag the view model polls, the plan the snapshot carries — is what the production code did.

@Suite("Break-it, sound: the real bridge", .serialized, .timeLimit(.minutes(5)), .attachingLogTail)
struct BreakItSoundBridgeTests {
    /// A 2 s AC-3 tone (Tests/Fixtures/breakit-sound/README.md): Apple's decoder delivers 288 frames fewer than the
    /// file's `length` says, then the next read throws — as every AC-3 and E-AC-3 file in the corpus does.
    private static let shortReadAC3 = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/breakit-sound/tone-ac3-mono-48k.m4a")

    @Test("BI-S05: a 48 kHz AC-3 / E-AC-3 track's end comes only once its last frame has played, not ~1 s early")
    func shortReadEndIsNotEarly() async throws {
        let file = try AVAudioFile(forReading: Self.shortReadAC3)
        let seconds = Double(file.length) / file.processingFormat.sampleRate // 2.016 s; 2.010 s decodable
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        try await rig.play(Self.shortReadAC3)
        var renderedSeconds = 0.0
        var endedAt: Double?
        var lastSound = 0.0
        while renderedSeconds < seconds + 1 {
            let block = try await rig.render(frames: 4800)
            if let loud = block[0].lastIndex(where: { abs($0) > 1e-3 }) {
                lastSound = renderedSeconds + Double(loud) / MultichannelDeviceRig.graphRate
            }
            renderedSeconds += 0.1
            if endedAt == nil, rig.bridge.gaplessPlaybackEnded {
                endedAt = renderedSeconds
            }
        }
        await rig.finish()
        let ended = try #require(endedAt, "the track never ended")
        // The view model stops at the end of the queue as the flag goes up (S-1), and a seam counts there: so the
        // flag must not rise before the audio it ends has played. Measured: up at 1.2 s of a 2.0 s file, the tone
        // sounding until 2.0 s — AVAudioPlayerNode fires a segment's completion when its read-ahead meets the
        // decoder's error, ~1 s before the end (the bare node does the same; FLAC's comes at the end).
        #expect(ended >= seconds - 0.1,
                "the end came at \(ended) s of a \(seconds) s track; its tone sounded until \(lastSound) s")
    }

    @Test("BI-S07: a fresh start of the same file with a NEW decision plays the new plan (the second play is exact)")
    func replayWithANewDecisionReplans() async throws {
        // FoldBadgeBridgeTests' 5.1 fixture: unmeasured on its first play, measured by its second (the founder,
        // 2026-10-26: "quieter and clean … exact from the second play").
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A))
        let url = try MultichannelFixture.write(layout: layout, rate: 48000, name: "bis-replay")
        defer { try? FileManager.default.removeItem(at: url) }
        let unmeasured = TrackLevelingDecision(
            mode: .unknownCut, source: .unknownCut, continuousWithPrevious: false,
            unfolded: .init(loudness: nil, truePeak: nil), folded: nil, roles: []
        )
        let measured = TrackLevelingDecision(
            mode: .leveled, source: .analysis, continuousWithPrevious: false,
            unfolded: .init(loudness: -20, truePeak: -6),
            folded: .init(loudness: [-21, -21, -21, -21], truePeak: [-4, -4, -4, -4], variant: 0),
            roles: [1, 2, 3, 4, 5, 6], peakRate: 48000
        )
        rig.bridge.holdStartDecision(unmeasured, for: url)
        try await rig.play(url)
        _ = try await rig.render(frames: 4800)
        #expect(rig.bridge.snapshot().signalPath.leveling?.foldMeasured == false, "the first play is unmeasured")

        // Played again from the top — after a stop, Play on the same row — with the analysis that landed meanwhile.
        rig.bridge.holdStartDecision(measured, for: url)
        try await rig.play(url)
        _ = try await rig.render(frames: 4800)
        let readout = try #require(rig.bridge.snapshot().signalPath.leveling)
        #expect(readout.foldMeasured, "the second play still plans the first play's worst-case trim (· measuring)")
        #expect(readout.mode == .leveled, "the second play still plays the unknown cut: \(readout.mode)")
        await rig.finish()
    }
}
