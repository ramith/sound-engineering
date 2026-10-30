@testable import AdaptiveSound
import AudioDSP
@preconcurrency import AVFoundation
import Foundation
import LevelingKit
import PlaybackQueueKit
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

    @Test("BI-S09: a mono file on a stereo output is leveled as the dual mono it plays as (+3.01 LU, F8)")
    func monoIsLeveledAsDualMono() async throws {
        // Design F8 and the founder's XM4 listen (2026-10-26): a mono file plays on both sides at 0 dB, so its heard
        // loudness is its one-channel measure + 3.01 LU, and the planner levels that. A quiet mono file the peak cap
        // does not bind: L −30 LUFS, TP −20 dBTP → g = −18 − (−30 + 3.01) = +8.99 dB (not +12).
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        let mono = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Mono))
        let url = try MultichannelFixture.write(layout: mono, rate: 48000, name: "bis-mono")
        defer { try? FileManager.default.removeItem(at: url) }
        let decision = TrackLevelingDecision(mode: .leveled, source: .analysis, continuousWithPrevious: false,
                                             unfolded: .init(loudness: -30, truePeak: -20), folded: nil,
                                             roles: [UInt8(AsChannelRoleC.rawValue)], peakRate: 48000)
        rig.bridge.holdStartDecision(decision, for: url)
        try await rig.play(url)
        _ = try await rig.render(frames: 4800)
        let plan = try #require(rig.bridge.leveling.audiblePlan)
        let output = rig.bridge.leveling.outputState
        let loud = plan.levelGainDb - 8.99
        let state = "\(output.sourceChannels) source channel(s) on \(output.outputChannels) output(s)"
        #expect(abs(loud) < 0.01, "g \(plan.levelGainDb) dB, \(loud) dB loud: no mono rule (output state: \(state))")
        await rig.finish()
    }

    @Test("BI-S08: a mode change the view model sent before it saw a seam never plans the new song from the old one's")
    func modeChangeRacingASeam() async throws {
        // Song A plays; song B is armed with its decision (g +2 dB). The seam passes on the engine; the view model,
        // whose tick has not sampled it yet (≤ 50 ms), still thinks A plays — the listener changes the mode, and it
        // sends A's new decision as `current` and B's as `next`. The decision carries no song.
        let rig = try await EnhancedTransportRig.playing([440], rate: 48000, frames: 24000, thenNext: 48000,
                                                         name: "bis-race")
        let next = try rig.writeTrack([440], named: "bis-race-b", rate: 48000, frames: 24000 ..< 120_000)
        let songB = Self.measured(-20, peak: -8)
        await rig.bridge.setNextTrack(next, ticket: OnDeckTicket(session: 0, sequence: 2), leveling: songB)
        _ = try #require(await rig.samples(frames: 24000 + 9600))
        try await until("the seam to be counted") { rig.bridge.gaplessTransitionCount == 1 }
        let atSeam = try #require(rig.bridge.leveling.audiblePlan)
        #expect(abs(atSeam.levelGainDb - 2) < 1e-9, "the precondition: B plays its own g")

        rig.bridge.applyLevelingChange(current: Self.measured(-24, peak: -10), next: songB) // A's, then B's
        let after = try #require(rig.bridge.leveling.audiblePlan)
        #expect(abs(after.levelGainDb - 2) < 1e-9,
                "song B now plays song A's decision: g \(after.levelGainDb) dB instead of +2 dB, to its end")
        await rig.finish()
    }

    /// A stereo track measured at the engine's rate.
    private static func measured(_ loudness: Double, peak: Double) -> TrackLevelingDecision {
        TrackLevelingDecision(mode: .leveled, source: .analysis, continuousWithPrevious: false,
                              unfolded: .init(loudness: loudness, truePeak: peak), folded: nil, roles: [1, 2],
                              peakRate: 48000)
    }
}
