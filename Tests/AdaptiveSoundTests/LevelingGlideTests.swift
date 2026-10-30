@testable import AdaptiveSound
import AudioDSP
@preconcurrency import AVFoundation
import Foundation
import LevelingKit
import RigKit
import Testing
import TrackLoudnessKit

// MARK: - Both units move alike (R1.1-B, level-and-fold §1.3, NI-4; review S3, N16)

//
// A plan reaches the effects unit (the leveling gain g, and G from the −ΔL profile) and the spatial unit (the fold's
// trim) in the same turn. When the listener's mode change trades one for the other — an album's shared trim against
// a track's own, say — the two must move along one curve, or the level swells or dips while they glide. And a plan on
// another −ΔL basis than the saved profile in force must bring that basis's saved profile with it.

@Suite("Leveling — both units move alike (S3, N16)", .serialized, .timeLimit(.minutes(3)), .attachingLogTail)
struct LevelingGlideTests {
    /// The fixture's order (MPEG 5.1 A) and the roles the resolver gives it.
    private static let roles: [UInt8] = [1, 2, 3, 4, 5, 6]

    /// A 5.1 track's decision whose fold measures `foldedLufs` LUFS at `foldedPeak` dBTP (every LFE variant alike),
    /// its N channels well under the ceiling.
    private static func surround(_ foldedLufs: Double, foldedPeak: Double, variant: Int = 0,
                                 profiles: [CompactLoudnessProfile] = []) -> TrackLevelingDecision {
        TrackLevelingDecision(
            mode: .leveled, source: .analysis, continuousWithPrevious: false,
            unfolded: .init(loudness: foldedLufs, truePeak: -10),
            folded: .init(loudness: [Double](repeating: foldedLufs, count: 4),
                          truePeak: [Double](repeating: foldedPeak, count: 4), variant: variant),
            roles: roles, peakRate: 48000, profiles: profiles
        )
    }

    /// A flat saved profile on `basis`, on the grid the engine rebuilds (1/12 octave at 48 kHz, one block): the band
    /// count is the first the engine's own rebuild takes.
    private static func engineProfile(_ basis: CompactLoudnessProfile.Basis) throws -> CompactLoudnessProfile {
        func flat(_ bands: Int) -> CompactLoudnessProfile {
            CompactLoudnessProfile(basis: basis, sampleRate: 48000, bandsPerOctave: 12, bandCount: bands,
                                   blockCount: 1, blockStrideHops: 1, powers: [UInt16](repeating: 0x3C00, count: bands))
        }
        let bands = try #require((1 ... 400).first { SavedLoudnessProfile(flat($0)) != nil }, "no grid rebuilds")
        return flat(bands)
    }

    @Test("LG-1: a mode change that trades the effects gain for the fold's trim keeps the level still while both glide")
    func aModeChangeTradingGainForTrimKeepsTheLevel() async throws {
        // Unknown transport (C_work −1.28 dBTP). Before: a hot fold (TP_F +2) trimmed −3.28 dB, g 0 — the trimmed
        // fold sits at the ceiling, so g is capped at 0. After: the fold's own peak under the ceiling (trim 0), the
        // loudness 3.28 LU higher, so g −3.28 dB. The net is the same; only the split moves.
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A))
        let url = try MultichannelFixture.write(layout: layout, rate: 48000, name: "lg-trade")
        defer { try? FileManager.default.removeItem(at: url) }
        rig.bridge.holdStartDecision(LevelingStart(decision: Self.surround(-16, foldedPeak: 2), listen: .newPlay),
                                     for: url)
        try await rig.play(url)
        _ = try await rig.render(frames: 4800)
        let before = try #require(rig.bridge.leveling.audiblePlan)

        let after = Self.surround(-18 - (before.levelGainDb + before.foldTrimDb), foldedPeak: -8)
        await rig.bridge.applyLevelingChange(current: SongLeveling(url: url, decision: after), next: nil)
        let changed = try #require(rig.bridge.leveling.audiblePlan)
        let netBefore = before.levelGainDb + before.foldTrimDb
        let netAfter = changed.levelGainDb + changed.foldTrimDb
        #expect(abs(before.foldTrimDb + 3.28) < 0.01 && changed.foldTrimDb == 0 && abs(netAfter - netBefore) < 1e-6,
                "the precondition: trim \(before.foldTrimDb) → \(changed.foldTrimDb), net \(netBefore) → \(netAfter)")

        // L′ carries L at 1.0: its tone, read every 20 ms through the glides (τ 0.15 s), to the fixture's end.
        let output = try await rig.render(frames: 28800)
        let window = 960
        var worst = 0.0
        for start in stride(from: 0, to: output[0].count - window + 1, by: window) {
            let level = MultichannelFixture.toneAmplitude(output[0][start ..< start + window],
                                                          frequency: MultichannelFixture.toneHz(0))
            let levelDb = 20 * log10(level / Double(MultichannelFixture.level))
            worst = max(worst, abs(levelDb - netBefore))
        }
        #expect(worst < 0.1, "the level moved \(worst) dB off \(netBefore) dB while the units glided")
        await rig.finish()
    }

    @Test("LG-3: an output change moves the fold's trim on the effects unit's 10 ms glide, never in a step (S4)")
    func anOutputChangeGlidesTheTrim() async throws {
        // Wired → Bluetooth under a measured fold (TP_F −1 dBTP, g +0.62 dB frozen): the protective re-plan (F5)
        // trims the fold −0.90 dB while it plays, and the effects unit stays where it is.
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A))
        let url = try MultichannelFixture.write(layout: layout, rate: 48000, name: "lg-output")
        defer { try? FileManager.default.removeItem(at: url) }
        rig.bridge.levelingTransportChanged(kAudioDeviceTransportTypeBuiltIn)
        rig.bridge.holdStartDecision(LevelingStart(decision: Self.surround(-21, foldedPeak: -1), listen: .newPlay),
                                     for: url)
        try await rig.play(url)
        _ = try await rig.render(frames: 4800)
        rig.bridge.levelingTransportChanged(kAudioDeviceTransportTypeBluetooth)
        let plan = try #require(rig.bridge.leveling.audiblePlan)
        #expect(plan.foldTrimDb < -0.5, "the precondition: the protective re-plan trims (\(plan.foldTrimDb) dB)")

        // L′ carries L at 1.0: its tone in 10 ms windows (every tone whole in one). τ = 10 ms is 480 frames; the
        // backstop's 3 ms look-ahead delays the output.
        let output = try await rig.render(frames: 4800)
        func levelDb(_ window: Range<Int>) -> Double {
            20 * log10(MultichannelFixture.toneAmplitude(output[0][window], frequency: MultichannelFixture.toneHz(0))
                / Double(MultichannelFixture.level))
        }
        let final = plan.levelGainDb + plan.foldTrimDb
        #expect(levelDb(480 ..< 960) - final > 0.1,
                "10–20 ms after the change the trim had already landed: \(levelDb(480 ..< 960)) dB, final \(final)")
        #expect(abs(levelDb(4320 ..< 4800) - final) < 0.01, "it never landed: \(levelDb(4320 ..< 4800)) dB")
        await rig.finish()
    }

    @Test("LG-2: a mode change onto another −ΔL basis sends that basis's saved profile before its plan (S3)")
    func aModeChangeOnAnotherBasisSendsItsSavedProfile() throws {
        let state = EngineLevelingState()
        var output = AsOutputState.unknownStereo
        output.sourceChannels = 6
        withUnsafeMutableBytes(of: &output.sourceRoles) { slots in
            for (slot, role) in Self.roles.enumerated() {
                slots[slot] = role
            }
        }
        _ = state.configureOutput(output)
        let omitted = try [Self.engineProfile(.decoded), Self.engineProfile(.fold(lfeVariant: 0))]
        let included = try [Self.engineProfile(.decoded), Self.engineProfile(.fold(lfeVariant: 2))]
        let url = URL(fileURLWithPath: "/nonexistent/lg-basis.flac")
        var sent: [(event: UInt32, basis: CompactLoudnessProfile.Basis?)] = []
        let effects: EngineLevelingState.EffectsDelivery = { delivery in
            sent.append((delivery.event.rawValue, delivery.saved?.basis))
            return 1
        }
        state.holdStart(.init(url: url, decision: Self.surround(-20, foldedPeak: -8, variant: 0, profiles: omitted)))
        _ = state.becameAudible(url, token: 7, gaplessSeam: false, unit: 1, effects: effects)
        #expect(sent.last?.basis == .fold(lfeVariant: 0), "the precondition: the play's saved profile, LFE omitted")

        // Album mode includes the LFE (the group's verdict): the plan plays the fold at variant 2.
        let album = EngineLevelingState.Pending(url: url, decision: Self.surround(-20, foldedPeak: -8, variant: 2,
                                                                                  profiles: included))
        state.changeMode(current: album, next: nil, effects: effects)
        #expect(sent.last?.event == AsPlanEventModeChange.rawValue)
        #expect(sent.last?.basis == .fold(lfeVariant: 2), "the mode change kept G on the old basis: \(sent)")

        // Back to a plan on the basis in force: nothing to re-send.
        state.changeMode(current: album, next: nil, effects: effects)
        #expect(sent.last?.basis == nil, "the same basis re-sent its profile")
    }
}
