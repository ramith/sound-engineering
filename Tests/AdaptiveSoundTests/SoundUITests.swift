// SOUND-UI — what the sound UI shows (R1.1-B W5, lane 3-B): the shared "Off in bit-perfect mode" row state and its
// registry (US-R1F-20 items 1–2), the Pure card's sentence (item 3), "Volume restored" (item 4), the fold's badge and
// Pure's reason (US-R1F-08 item 6), crossfeed on a folded file (item 7), and the Leveling row's words (US-R1F-10
// item 2). On the real view model and the real `SignalPathInfo`.

@testable import AdaptiveSound
import AudioDSP
import Foundation
import LevelingKit
import RigKit
import SettingsKit
import Testing

@MainActor
@Suite("Sound UI — the Pure row state, the fold, the toast, the Leveling row (R1.1-B)", .timeLimit(.minutes(3)),
       .attachingLogTail)
struct SoundUITests {
    // MARK: The shared row state

    @Test("SOUND-UI-01: the DSP rows follow the path in use, never the switch; Leave Pure waits for the next start")
    func rowsFollowThePathInUse() async throws {
        let player = try await FakePlayer.launched(tracks: 1)
        let model = player.vm
        #expect(model.dspRowAvailability == .live)
        model.pureModeEnabled = true
        #expect(model.dspRowAvailability == .live, "Pure asked for, Enhanced plays: the rows work")
        model.signalPath.path = .pure
        #expect(model.dspRowAvailability == .notInBitPerfectMode(leaving: false))
        model.leavePure()
        #expect(!model.pureModeEnabled)
        #expect(model.dspRowAvailability == .notInBitPerfectMode(leaving: true),
                "Pure plays until the next start: still inert, and it says when Enhanced comes back")
        model.signalPath.path = .enhanced
        #expect(model.dspRowAvailability == .live)
    }

    @Test("SOUND-UI-02: every registered DSP row wears the shared state in the UI — its gate and its note")
    func registryIsWornByTheUI() throws {
        let ui = try Self.uiSource()
        for row in DSPRow.allCases {
            #expect(ui.contains("bitPerfectGate(.\(row.rawValue),"), "\(row) has no bitPerfectGate in the UI")
            #expect(ui.contains("BitPerfectRowNote(row: .\(row.rawValue),"), "\(row) has no BitPerfectRowNote")
        }
    }

    /// Every Swift file of the app's UI, as one text.
    private static func uiSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/AdaptiveSound/UI")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var text = ""
        for case let url as URL in files where url.pathExtension == "swift" {
            text += try String(contentsOf: url, encoding: .utf8)
        }
        #expect(!text.isEmpty, "the UI sources at \(root.path)")
        return text
    }

    @Test("SOUND-UI-03: the Pure card's sentence on the two untouched states, as the story words it")
    func pureCardSentence() {
        #expect(PureModeSettingsSection.twoUntouchedStates
            == "Pure sends the file to your device untouched; Enhanced with every effect off leaves the sound "
            + "untouched too, but plays through the app’s engine, which is what lets leveling, surround folding "
            + "and the effects work.")
    }

    // MARK: "Volume restored"

    @Test("SOUND-UI-04: the engine says Pure gave the volume back: \"Volume restored\", once per time")
    func volumeRestoredToast() async throws {
        let player = try await FakePlayer.launched(tracks: 0)
        #expect(player.vm.volumeRestoredToast.toast == nil, "no toast while Pure touched nothing")
        player.engine.restorePureVolume()
        let first = try #require(player.vm.volumeRestoredToast.toast)
        #expect(first.message == "Volume restored")
        player.engine.restorePureVolume()
        let second = try #require(player.vm.volumeRestoredToast.toast)
        #expect(second.token == first.token + 1, "a second give-back is a second toast")
    }

    // MARK: The fold

    private static func fold(channels: Int, fromPlan: Bool = true) -> FoldState {
        FoldState(sourceChannels: channels, outputChannels: 2, fromPlan: fromPlan, trimDb: -6, lfeGain: 0,
                  backstopPeakGrDb: 0)
    }

    private static func readout(measured: Bool, layout: String?) -> LevelingReadout {
        LevelingReadout(mode: .leveled, gainDb: -4.2, foldMeasured: measured, sourceLayout: layout)
    }

    @Test("SOUND-UI-05: the badge shows exactly while the fold plays — \"· measuring\" on a first, unmeasured play")
    func foldBadge() {
        var info = SignalPathInfo()
        #expect(info.foldBadge == nil, "nothing folds")
        info.fold = Self.fold(channels: 6)
        info.leveling = Self.readout(measured: true, layout: "5.1")
        #expect(info.foldBadge == "5.1 → stereo")
        #expect(info.spokenFoldBadge == "5.1 folded to stereo")
        info.leveling = Self.readout(measured: false, layout: "5.1")
        #expect(info.foldBadge == "5.1 → stereo · measuring")
        #expect(SignalPathAccessibility.value(for: info).contains("5.1 folded to stereo, measuring"))
        info.fold = Self.fold(channels: 6, fromPlan: false)
        #expect(info.foldBadge == "5.1 → stereo", "the layout's fold before the plan: not a verdict yet")
        info.fold = Self.fold(channels: 5)
        info.leveling = Self.readout(measured: true, layout: "5.0")
        #expect(info.foldBadge == "5.0 → stereo", "a 5.0 file names its own layout")
        info.leveling = nil
        info.fold = Self.fold(channels: 8)
        #expect(info.foldBadge == "7.1 → stereo", "no roles known: 8 channels read as 7.1")
        info.path = .pure
        #expect(info.foldBadge == nil, "Pure never folds")
    }

    @Test("SOUND-UI-06: Pure's reason on a folded file says what plays: \"…so Enhanced plays it, folded to stereo\"")
    func pureReasonOnAFold() {
        var info = SignalPathInfo()
        info.pureReason = .channelCountMismatch
        #expect(PureModeReason.channelCountMismatch.detail(in: info, masterGain: 0)
            == "This track has a different number of channels than your device, so Enhanced is playing it.")
        info.fold = Self.fold(channels: 6)
        #expect(PureModeReason.channelCountMismatch.detail(in: info, masterGain: 0)
            == "This track has 6 channels and your output has 2, so Enhanced plays it, folded to stereo.")
    }

    @Test("SOUND-UI-07: crossfeed on a folded file: no XF, and the Headphones section says it is not active")
    func crossfeedOnAFold() {
        var info = SignalPathInfo()
        info.crossfeedStrength = .strong
        info.crossfeedEngaged = true
        #expect(!info.crossfeedHeldBySurround && info.audibleCrossfeed == .strong, "stereo: XF plays")
        info.fold = Self.fold(channels: 6)
        info.crossfeedEngaged = false
        #expect(info.crossfeedHeldBySurround)
        #expect(info.audibleCrossfeed == nil, "no XF chip when nothing plays")
        info.crossfeedStrength = nil
        #expect(!info.crossfeedHeldBySurround, "crossfeed off (or not on headphones): nothing to say")
    }

    // MARK: The Leveling row

    @Test("SOUND-UI-08: the Leveling row's words — the four choices, the target, the song's gain and its source")
    func levelingRowWords() {
        #expect(LevelingSetting.allCases.map(LevelingRowText.title) == ["Off", "Auto", "Album", "Track"])
        for setting in LevelingSetting.allCases {
            #expect(LevelingRowText.meaning(of: setting).hasSuffix("."))
        }
        #expect(LevelingRowText.target == "Target −18 LUFS")
        let leveled = LevelingReadout(mode: .leveled, gainDb: -4.24, foldMeasured: true, sourceLayout: nil)
        #expect(LevelingRowText.nowPlaying(setting: .track, readout: leveled, source: .analysis)?.text
            == "This song -4.2 dB, from analysis")
        #expect(LevelingRowText.nowPlaying(setting: .album, readout: leveled, source: .tags)?.text
            == "This song -4.2 dB, from file tags")
        let unknown = LevelingReadout(mode: .unknownCut, gainDb: -5, foldMeasured: true, sourceLayout: nil)
        #expect(LevelingRowText.nowPlaying(setting: .auto, readout: unknown, source: .unknownCut)?.text
            == "This song -5.0 dB, loudness unknown")
        #expect(LevelingRowText.nowPlaying(setting: .auto, readout: unknown, source: .unknownCut)?.spoken
            == "This song minus 5 decibels, loudness unknown")
        #expect(LevelingRowText.nowPlaying(setting: .off, readout: leveled, source: .analysis) == nil,
                "Leveling Off: no gain to show")
        #expect(LevelingRowText.nowPlaying(setting: .track, readout: nil, source: nil) == nil, "nothing planned")
    }

    @Test("SOUND-UI-09: the readout is the engine's plan — its mode, gain, measured fold and the layout's name")
    func readoutFromThePlan() {
        var plan = AsTrackPlan()
        plan.mode = UInt8(AsLevelingModeLeveled.rawValue)
        plan.levelGainDb = -3.5
        plan.foldFromAnalysis = 0
        var output = AsOutputState()
        output.sourceChannels = 6
        let roles: [AsChannelRole] = [AsChannelRoleL, AsChannelRoleR, AsChannelRoleC, AsChannelRoleLfe,
                                      AsChannelRoleLs, AsChannelRoleRs]
        withUnsafeMutableBytes(of: &output.sourceRoles) { bytes in
            for (index, role) in roles.enumerated() {
                bytes[index] = UInt8(role.rawValue)
            }
        }
        let readout = LevelingReadout(plan: plan, output: output)
        #expect(readout == LevelingReadout(mode: .leveled, gainDb: -3.5, foldMeasured: false, sourceLayout: "5.1"))
        plan.mode = UInt8(AsLevelingModeUnknownCut.rawValue)
        plan.foldFromAnalysis = 1
        output.sourceChannels = 5
        withUnsafeMutableBytes(of: &output.sourceRoles) { $0[3] = UInt8(AsChannelRoleLs.rawValue) }
        withUnsafeMutableBytes(of: &output.sourceRoles) { $0[4] = UInt8(AsChannelRoleRs.rawValue) }
        let fivePointOh = LevelingReadout(plan: plan, output: output)
        #expect(fivePointOh.mode == .unknownCut && fivePointOh.foldMeasured && fivePointOh.sourceLayout == "5.0")
        #expect(LevelingReadout.layoutName(roles: [0, 0, 0]) == nil, "no role known: no name")
    }
}
