// ROLES — the one channel-role resolver from Swift (R1.1-B, level-and-fold §S1b): AVAudioChannelLayout as the
// decoder reports it → AsChannelRole per slot, through AudioDSP's asResolveChannelRoles. The layouts are the
// corpus's cases: AAC / ALAC 5.1 (C L R Ls Rs LFE), the FLAC 5.1 with a rear pair, the 7-channel file with one
// description per channel and no tag, and label-less D0…Dn signals (the count fallback, WAV order).

import AudioDSP
import AVFoundation
import Testing
@testable import TrackLoudnessKit

@Suite("ChannelRoles — roles from labels, never from position")
struct ChannelRolesTests {
    private static let (left, right, centre, lfe) = (role(AsChannelRoleL), role(AsChannelRoleR),
                                                     role(AsChannelRoleC), role(AsChannelRoleLfe))
    private static let (sideLeft, sideRight) = (role(AsChannelRoleLs), role(AsChannelRoleRs))
    private static let (backLeft, backRight) = (role(AsChannelRoleLb), role(AsChannelRoleRb))

    private static func role(_ value: AsChannelRole) -> UInt8 {
        UInt8(value.rawValue)
    }

    @Test("ROLES-01: a tag names each slot — AAC / ALAC 5.1 and the FLAC 5.1's rear pair")
    func tags() throws {
        let aac = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_AAC_5_1))
        #expect(ChannelRoles.resolve(channelCount: 6, layout: aac)
            == [Self.centre, Self.left, Self.right, Self.sideLeft, Self.sideRight, Self.lfe])
        let rear = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_WAVE_5_1_B))
        #expect(ChannelRoles.resolve(channelCount: 6, layout: rear)
            == [Self.left, Self.right, Self.centre, Self.lfe, Self.backLeft, Self.backRight])
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channelLayout: aac)
        #expect(ChannelRoles.resolve(format: format) == ChannelRoles.resolve(channelCount: 6, layout: aac))
    }

    @Test("ROLES-02: tag 0 with a description per channel — the corpus's 7.0 FLAC (L R C Rls Rrs Ls Rs)")
    func descriptions() throws {
        let labels: [AudioChannelLabel] = [kAudioChannelLabel_Left, kAudioChannelLabel_Right,
                                           kAudioChannelLabel_Center, kAudioChannelLabel_RearSurroundLeft,
                                           kAudioChannelLabel_RearSurroundRight, kAudioChannelLabel_LeftSurround,
                                           kAudioChannelLabel_RightSurround]
        let layout = try #require(Self.described(labels))
        #expect(ChannelRoles.resolve(channelCount: 7, layout: layout)
            == [Self.left, Self.right, Self.centre, Self.backLeft, Self.backRight, Self.sideLeft, Self.sideRight])
    }

    @Test("ROLES-03: no labels (none, DiscreteInOrder, D0…D5) — the count, in WAV order")
    func countFallback() throws {
        let wav51 = [Self.left, Self.right, Self.centre, Self.lfe, Self.backLeft, Self.backRight]
        #expect(ChannelRoles.resolve(channelCount: 6, layout: nil) == wav51)
        let discrete = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 6))
        #expect(ChannelRoles.resolve(channelCount: 6, layout: discrete) == wav51)
        let labels = (0 ..< 6).map { AudioChannelLabel(kAudioChannelLabel_Discrete_0 + $0) }
        let dLabels = try #require(Self.described(labels))
        #expect(ChannelRoles.resolve(channelCount: 6, layout: dLabels) == wav51)
        #expect(ChannelRoles.resolve(channelCount: 1, layout: nil) == [Self.role(AsChannelRoleMono)])
    }

    @Test("ROLES-04: no channels, or more than the pipeline carries")
    func widths() {
        #expect(ChannelRoles.resolve(channelCount: 0, layout: nil).isEmpty)
        let unknown = Self.role(AsChannelRoleUnknown)
        #expect(ChannelRoles.resolve(channelCount: 10, layout: nil) == [UInt8](repeating: unknown, count: 8))
    }

    /// A layout with one description per channel and no tag (UseChannelDescriptions).
    private static func described(_ labels: [AudioChannelLabel]) -> AVAudioChannelLayout? {
        let head = MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions) ?? 0
        let size = head + labels.count * MemoryLayout<AudioChannelDescription>.stride
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size,
                                                   alignment: MemoryLayout<AudioChannelLayout>.alignment)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let layout = raw.bindMemory(to: AudioChannelLayout.self, capacity: 1)
        layout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
        layout.pointee.mNumberChannelDescriptions = UInt32(labels.count)
        let slots = (raw + head).bindMemory(to: AudioChannelDescription.self, capacity: labels.count)
        for (slot, label) in labels.enumerated() {
            slots[slot].mChannelLabel = label
        }
        return AVAudioChannelLayout(layout: layout)
    }
}
