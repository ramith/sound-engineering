@testable import AdaptiveSound
import AudioDSP
@preconcurrency import AVFoundation
import Foundation
import RigKit
import SettingsKit
import Testing

// MARK: - The fold through the real bridge (R1.1-B; level-and-fold §S2, M1; US-R1F-08; KI-SND-06)

//
// The real bridge on an offline stereo device (`MultichannelDeviceRig`), playing generated one-tone-per-channel
// files (`MultichannelFixture`): the layout's fold the bridge publishes when it configures the graph, a plan
// published through the spatial unit's C-ABI (`asSpatialPublishPlan`, lane 1's BS.775 matrix behind it), and
// S2's crossfeed read-out.

@Suite("The fold through the real bridge", .serialized, .timeLimit(.minutes(5)))
struct FoldBridgeTests {
    /// The 5.1 fixture's order (WAVE / MPEG 5.1 A): L R C LFE Ls Rs.
    static let surround = kAudioChannelLayoutTag_MPEG_5_1_A
    static let lfeSlot = 3

    /// The amplitude of channel `channel`'s tone in `samples` (the rendered window).
    static func level(_ samples: [Float], channel: Int) -> Double {
        MultichannelFixture.toneAmplitude(samples[MultichannelFixture.window],
                                          frequency: MultichannelFixture.toneHz(channel))
    }

    static func decibels(_ amplitude: Double) -> Double {
        20 * log10(max(amplitude, 1e-12) / Double(MultichannelFixture.level))
    }

    @Test("FB-1: a 5.1 file folds before any plan — every main channel reaches L′ or R′, at a worst-case trim")
    func layoutFoldBeforeThePlan() async throws {
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        let layout = try #require(AVAudioChannelLayout(layoutTag: Self.surround))
        let url = try MultichannelFixture.write(layout: layout, rate: 48000, name: "fb1")
        defer { try? FileManager.default.removeItem(at: url) }
        try await rig.play(url)
        let output = try await rig.render(frames: MultichannelFixture.renderFrames)

        try #require(output.count == 2, "the stereo device renders two channels")
        for channel in 0 ..< 6 where channel != Self.lfeSlot {
            let loudest = max(Self.level(output[0], channel: channel), Self.level(output[1], channel: channel))
            #expect(Self.decibels(loudest) > -40, "channel \(channel) reaches the fold (\(Self.decibels(loudest)) dB)")
        }
        let fold = try #require(rig.bridge.snapshot().signalPath.fold)
        #expect(!fold.fromPlan, "no plan yet: the layout's fold")
        #expect(fold.trimDb <= -8.9, "the worst-case trim, never 0 (got \(fold.trimDb) dB)")
        #expect(fold.backstopPeakGrDb < 0.01, "the backstop sleeps (\(fold.backstopPeakGrDb) dB)")
        await rig.finish()
    }

    @Test("FB-2: the plan's fold through the spatial unit's C-ABI — BS.775 by role, the plan's trim, the LFE omitted")
    func planFoldThroughTheCABI() async throws {
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        let layout = try #require(AVAudioChannelLayout(layoutTag: Self.surround))
        let url = try MultichannelFixture.write(layout: layout, rate: 48000, name: "fb2")
        defer { try? FileManager.default.removeItem(at: url) }
        try await rig.play(url)

        var output = AsOutputState()
        output.engineRateHz = 48000
        output.sourceChannels = 6
        output.outputChannels = 2
        let roles: [AsChannelRole] = [AsChannelRoleL, AsChannelRoleR, AsChannelRoleC, AsChannelRoleLfe,
                                      AsChannelRoleLs, AsChannelRoleRs]
        withUnsafeMutableBytes(of: &output.sourceRoles) { slots in
            for (slot, role) in roles.enumerated() {
                slots[slot] = UInt8(role.rawValue)
            }
        }
        var plan = AsTrackPlan()
        plan.version = UInt32(AS_TRACK_PLAN_VERSION)
        plan.folds = 1
        plan.lfeVariant = UInt8(AsLfeVariantOmit.rawValue)
        plan.foldTrimDb = -3
        let published = rig.bridge.withSpatialAU {
            asSpatialPublishPlan($0, &plan, &output, UInt8(AsPlanEventFreshStart.rawValue))
        }
        try #require(published == true, "the spatial unit takes the plan")
        let rendered = try await rig.render(frames: MultichannelFixture.renderFrames)

        let (left, right) = (rendered[0], rendered[1])
        let centre = (Self.decibels(Self.level(left, channel: 2)), Self.decibels(Self.level(right, channel: 2)))
        #expect(abs(centre.0 - (-3.0103 - 3)) <= 0.05 && abs(centre.1 - (-3.0103 - 3)) <= 0.05,
                "the centre at −3.01 − 3 dB per side (got \(centre))")
        #expect(abs(Self.decibels(Self.level(left, channel: 0)) - -3) <= 0.05, "L at the trim in L′")
        #expect(Self.decibels(Self.level(right, channel: 0)) < -80, "L stays out of R′")
        #expect(Self.decibels(Self.level(left, channel: 4)) - (-3.0103 - 3) <= 0.05, "Ls at −3 dB in L′")
        #expect(Self.decibels(Self.level(left, channel: Self.lfeSlot)) < -80, "the LFE omitted")
        let fold = try #require(rig.bridge.snapshot().signalPath.fold)
        #expect(fold.fromPlan && fold.trimDb == -3 && !fold.lfeIncluded)
        await rig.finish()
    }

    @Test("FB-3 (KI-SND-06): crossfeed shows only where it plays — engaged on stereo, bypassed on a folded file")
    func crossfeedReadsTheEnginesBypass() async throws {
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        rig.bridge.publishCrossfeed(enabled: true, strength: .defaultStrength)
        let stereoLayout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo))
        let stereo = try MultichannelFixture.write(layout: stereoLayout, rate: 48000, name: "fb3-stereo")
        let surroundLayout = try #require(AVAudioChannelLayout(layoutTag: Self.surround))
        let surround = try MultichannelFixture.write(layout: surroundLayout, rate: 48000, name: "fb3-surround")
        defer {
            try? FileManager.default.removeItem(at: stereo)
            try? FileManager.default.removeItem(at: surround)
        }

        try await rig.play(stereo)
        _ = try await rig.render(frames: 4800)
        var path = rig.bridge.snapshot().signalPath
        path.crossfeedStrength = .defaultStrength // the view model's intent, copied in on its tick
        #expect(path.crossfeedEngaged == true, "crossfeed plays on a stereo file")
        #expect(path.audibleCrossfeed == .defaultStrength, "and the chip shows it")

        try await rig.play(surround)
        _ = try await rig.render(frames: 4800)
        path = rig.bridge.snapshot().signalPath
        path.crossfeedStrength = .defaultStrength
        #expect(path.crossfeedEngaged == false, "the engine bypasses crossfeed on a folded 5.1 file")
        #expect(path.audibleCrossfeed == nil, "so the chip does not show it")
        await rig.finish()
    }
}
