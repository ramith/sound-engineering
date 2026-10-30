// LEVEL-MONO — a mono song among stereo ones (review N1). A mono file plays on both sides of a stereo output at 0 dB
// (F8, the founder's XM4 listen): heard as dual mono, 3.01 LU above its one-channel measure. The decision builder
// compares a group's members as they are heard, and the planner applies the correction once, so every member of a
// mixed album plays at one leveling gain. The real decision builder, the app's C mirror and the C++ planner.

@testable import AdaptiveSound
import AudioDSP
import Foundation
import LevelingKit
import Testing

@Suite("Leveling: a mono song among stereo ones (review N1)")
struct LevelingMonoGroupTests {
    private static let stereoRoles = [UInt8(AsChannelRoleL.rawValue), UInt8(AsChannelRoleR.rawValue)]
    private static let monoRoles = [UInt8(AsChannelRoleMono.rawValue)]

    /// A measured song: `loudness` LUFS on its own channels, a −10 dBTP peak (the cap never binds here), 200 s,
    /// silence at both edges (no continuous run).
    private static func measured(_ loudness: Double, roles: [UInt8]) -> LevelingTrack.Measurement {
        LevelingTrack.Measurement(loudness: loudness, truePeak: -10, peakRate: 48000, roles: roles,
                                  durationSeconds: 200, headLoudness: -200, tailLoudness: -200, folded: nil)
    }

    /// What the planner makes of `decision` for a file with `roles`, played on a stereo output.
    private static func plan(_ decision: TrackLevelingDecision, roles: [UInt8]) -> AsTrackPlan {
        var leveling = AsTrackLeveling(decision)
        var output = AsOutputState.unknownStereo
        output.sourceChannels = UInt32(roles.count)
        withUnsafeMutableBytes(of: &output.sourceRoles) { slots in
            for index in slots.indices {
                slots[index] = index < roles.count ? roles[index] : UInt8(AsChannelRoleUnknown.rawValue)
            }
        }
        return asPlanTrack(&leveling, &output, nil)
    }

    @Test("LEVEL-MONO-01: a mixed mono/stereo album plays every member at one g, anchored on how each is heard")
    func oneGainForAMixedAlbum() {
        // −22 LUFS on one channel is heard at −18.99 on a stereo output: the album's loudest, over the stereo
        // song's −20. Album mode: g = −18 − (−18.99) = +0.99 dB for both songs.
        let library = LevelingLibrary(tracks: [
            "st": LevelingTrack(album: 9, measurement: Self.measured(-20, roles: Self.stereoRoles)),
            "mo": LevelingTrack(album: 9, measurement: Self.measured(-22, roles: Self.monoRoles)),
        ], albums: [9: ["st", "mo"]])
        let gains = [("st", Self.stereoRoles), ("mo", Self.monoRoles)].map { key, roles in
            Self.plan(library.decision(for: LevelingRequest(key: key, mode: .album)), roles: roles).levelGainDb
        }
        let expected = -18 - (-22 + 10 * log10(2.0))
        #expect(abs(gains[0] - expected) < 1e-9 && abs(gains[1] - expected) < 1e-9,
                "stereo member g \(gains[0]) dB, mono member g \(gains[1]) dB; the album's g is \(expected) dB")
    }

    @Test("LEVEL-MONO-02: the builder's dual mono is the planner's (F8, applied once, by the planner)")
    func oneDualMono() {
        let song = LevelingTrack(album: nil, measurement: Self.measured(-30, roles: Self.monoRoles))
        let alone = LevelingLibrary(tracks: ["mo": song])
        let decision = alone.decision(for: LevelingRequest(key: "mo", mode: .track))
        let plan = Self.plan(decision, roles: Self.monoRoles)
        #expect(decision.unfolded.loudness == -30) // a lone mono song's decision is its own one-channel measure
        #expect(abs(plan.loudnessLufs - (-30 + LevelingRules.dualMonoLu)) < 1e-9,
                "the planner heard \(plan.loudnessLufs) LUFS for a −30 LUFS mono song")
    }
}
