@testable import AdaptiveSound
import AudioDSP
@preconcurrency import AVFoundation
import Foundation
import LevelingKit
import RigKit
import Testing

// MARK: - The fold badge through the real bridge (R1.1-B W5, lane 3-B; US-R1F-08 item 6, founder 2026-10-26)

//
// The real bridge on an offline stereo device (lane 2's `MultichannelDeviceRig`): a 5.1 file starts with the
// decision a start carries (`holdStartDecision`, as `startAudio` does), the one planner plans it at audibility, and
// the main thread's snapshot carries the plan (`SignalPathInfo.leveling`). The badge reads "· measuring" exactly
// when the plan's trim is the worst case — the first play of a track nobody has measured — and plain
// "5.1 → stereo" once the track's measured fold plans it. Nothing is heard.

@Suite("The fold badge through the real bridge", .serialized, .timeLimit(.minutes(5)))
struct FoldBadgeBridgeTests {
    /// The fixture's order (MPEG 5.1 A): L R C LFE Ls Rs, the roles the resolver gives it.
    private static let surround = kAudioChannelLayoutTag_MPEG_5_1_A
    private static let roles: [UInt8] = [1, 2, 3, 4, 5, 6]

    /// A measured 5.1 track's decision: its fold's numbers at each LFE variant, the LFE omitted.
    private static let measured = TrackLevelingDecision(
        mode: .leveled, source: .analysis, continuousWithPrevious: false,
        unfolded: .init(loudness: -20, truePeak: -6),
        folded: .init(loudness: [-21, -21, -21, -21], truePeak: [-4, -4, -4, -4], variant: 0),
        roles: roles, peakRate: 48000
    )
    /// A track nobody has measured: the unknown rule, no fold numbers.
    private static let unmeasured = TrackLevelingDecision(
        mode: .unknownCut, source: .unknownCut, continuousWithPrevious: false,
        unfolded: .init(loudness: nil, truePeak: nil), folded: nil, roles: []
    )

    @Test("FOLD-BADGE-01: a first, unmeasured play reads \"5.1 → stereo · measuring\"; a measured one \"5.1 → stereo\"",
          arguments: [(false, "5.1 → stereo · measuring"), (true, "5.1 → stereo")])
    func badgeFollowsThePlan(isMeasured: Bool, badge: String) async throws {
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        let layout = try #require(AVAudioChannelLayout(layoutTag: Self.surround))
        let url = try MultichannelFixture.write(layout: layout, rate: 48000, name: "badge-\(isMeasured)")
        defer { try? FileManager.default.removeItem(at: url) }
        rig.bridge.holdStartDecision(isMeasured ? Self.measured : Self.unmeasured, for: url)
        try await rig.play(url)
        _ = try await rig.render(frames: 4800)

        let path = rig.bridge.snapshot().signalPath
        let readout = try #require(path.leveling, "the snapshot carries the audible plan")
        #expect(readout.foldMeasured == isMeasured)
        #expect(readout.sourceLayout == "5.1", "named from the source's roles")
        #expect(path.fold?.fromPlan == true, "the fold plays the track's plan")
        #expect(path.foldBadge == badge)
        if !isMeasured {
            // Quieter and clean (founder, 2026-10-26): the fold's worst-case trim, and the unknown rule on top of it
            // only as far as the unknown peak's cap — the trim already cuts more than −5 dB (§1.3).
            let trim = Double(path.fold?.trimDb ?? 0)
            #expect(readout.mode == .unknownCut && trim <= -8, "the worst-case trim (\(trim) dB)")
            #expect(trim + readout.gainDb <= -9, "in all \(trim + readout.gainDb) dB under the file")
        }
        await rig.finish()
    }
}
