@testable import AdaptiveSound
import CoreAudio
import EQEditKit
import Foundation
import RigKit
import SettingsKit
import Testing

// MARK: - The DSP rows keep the path that last played (R1.1-B fix round, F4: the break-it's "Pure paused")

//
// The rows' state followed the path the engine reports, and a pause or a stop reports nothing playing (the bridge
// stores an empty signal path), so pausing in Pure made the EQ, Tone, crossfeed and Leveling rows go live — editable
// controls that do nothing, until Play brought Pure back and froze them again. The rule (coordinator, from the
// founder's decisions, 2026-10-30): pausing or stopping never changes the rows' state; they keep the path that last
// played. Before anything has played since launch they follow what a start would do on this device: Pure chosen and
// a device that can play bit-perfect → inert. The EQ screen's own Pure state follows the same rule. On the shipped
// view model over FakeEngine, the engine's reports going through the transport tick.

@MainActor
@Suite("The DSP rows keep the path that last played — paused, stopped, before the first song", .serialized,
       .timeLimit(.minutes(3)), .attachingLogTail)
struct PausedRowsTests {
    private static let speakers = AudioDeviceModel(
        id: 1, name: "MacBook Pro Speakers", sampleRate: 48000, bufferFrameSize: 512, uid: "BuiltInSpeakerDevice",
        modelUID: nil, transportType: kAudioDeviceTransportTypeBuiltIn, type: .builtin, isHeadphones: false
    )
    private static let xm4 = AudioDeviceModel(
        id: 3, name: "WH-1000XM4", sampleRate: 48000, bufferFrameSize: 512, uid: "xm4:output", modelUID: nil,
        transportType: kAudioDeviceTransportTypeBluetooth, type: .wireless, isHeadphones: true
    )

    /// Pure asked for and a song playing, on `path` as the engine reports it (with `reason` when Pure declined).
    private static func playing(on path: OutputPathKind, declinedFor reason: PureModeReason? = nil) async throws
        -> FakePlayer {
        let player = try await FakePlayer.launched(tracks: 2)
        player.vm.pureModeEnabled = true
        try await player.play(at: 0)
        player.engine.state.withLock { state in
            state.signalPath.path = path
            state.signalPath.achievedSampleRate = 48000
            state.signalPath.pureReason = reason
        }
        try player.tick()
        return player
    }

    /// What the engine reports once a stop or a pause has stopped it: nothing plays.
    private static func engineStopped(_ player: FakePlayer, interrupted: Bool = false) {
        player.engine.state.withLock { $0.signalPath = SignalPathInfo(interrupted: interrupted) }
    }

    /// The EQ screen of `player`'s view model, the EQ on.
    private static func eqScreen(of player: FakePlayer, _ world: IsolatedDefaults) -> EQViewModel {
        let eq = EQViewModel(audioViewModel: player.vm, defaults: world.defaults)
        eq.isOn = true
        return eq
    }

    @Test("ROWS-01: paused in Pure, the rows stay inert and the EQ screen still reads Pure")
    func pauseInPureKeepsTheRowsInert() async throws {
        let player = try await Self.playing(on: .pure)
        let world = IsolatedDefaults("PausedRows-01")
        let eq = Self.eqScreen(of: player, world)
        #expect(player.vm.dspRowAvailability == .notInBitPerfectMode(leaving: false))
        player.vm.pause()
        Self.engineStopped(player)
        try await player.vm.settled()
        try player.tick()
        #expect(!player.vm.isPlaying && player.vm.signalPath.path == .enhanced, "the engine reports nothing playing")
        #expect(player.vm.dspRowAvailability == .notInBitPerfectMode(leaving: false), "a pause never changes the rows")
        #expect(eq.audible == .pureMode, "the EQ screen keeps Pure's line and its Leave Pure")
    }

    @Test("ROWS-02: stopped in Pure, the rows stay inert")
    func stopInPureKeepsTheRowsInert() async throws {
        let player = try await Self.playing(on: .pure)
        player.vm.stopPlayback()
        Self.engineStopped(player)
        try await player.vm.settled()
        try player.tick()
        #expect(!player.vm.isPlaying)
        #expect(player.vm.dspRowAvailability == .notInBitPerfectMode(leaving: false), "a stop never changes the rows")
    }

    @Test("ROWS-03: Pure asked for but declined (Bluetooth): Enhanced played, so paused the rows stay live")
    func pauseAfterEnhancedKeepsTheRowsLive() async throws {
        let player = try await Self.playing(on: .enhanced, declinedFor: .bluetooth)
        player.vm.selectedDevice = Self.xm4
        #expect(player.vm.dspRowAvailability == .live)
        player.vm.pause()
        Self.engineStopped(player)
        try await player.vm.settled()
        try player.tick()
        #expect(player.vm.dspRowAvailability == .live, "what last played was Enhanced")
    }

    @Test("ROWS-04: the output lost while Pure plays — the pause keeps the rows inert")
    func deviceLossInPureKeepsTheRowsInert() async throws {
        let player = try await Self.playing(on: .pure)
        Self.engineStopped(player, interrupted: true)
        try player.tick()
        #expect(!player.vm.isPlaying && player.vm.signalPath.interrupted)
        #expect(player.vm.dspRowAvailability == .notInBitPerfectMode(leaving: false))
    }

    @Test("ROWS-05: Leave Pure while paused says when Enhanced comes back; the next start plays Enhanced, live")
    func leavePureWhilePaused() async throws {
        let player = try await Self.playing(on: .pure)
        player.vm.pause()
        Self.engineStopped(player)
        try await player.vm.settled()
        try player.tick()
        player.vm.leavePure()
        #expect(player.vm.dspRowAvailability == .notInBitPerfectMode(leaving: true))
        player.vm.play()
        try await player.vm.settled()
        try await until("the song to play again") { player.vm.isPlaying && player.vm.transportCommand == nil }
        player.engine.state.withLock { $0.signalPath.path = .enhanced; $0.signalPath.achievedSampleRate = 48000 }
        try player.tick()
        #expect(player.vm.dspRowAvailability == .live)
    }

    @Test("ROWS-06: before any song has played — what a start would do on this device")
    func beforeTheFirstSongTheDeviceDecides() async throws {
        let player = try await FakePlayer.launched(tracks: 1)
        let world = IsolatedDefaults("PausedRows-06")
        let eq = Self.eqScreen(of: player, world)
        player.vm.selectedDevice = Self.speakers
        #expect(player.vm.dspRowAvailability == .live, "Pure not chosen: a start plays Enhanced")
        player.vm.pureModeEnabled = true
        #expect(player.vm.dspRowAvailability == .notInBitPerfectMode(leaving: false),
                "Pure chosen on the built-in output: a start plays Pure")
        #expect(eq.audible == .pureMode)
        player.vm.selectedDevice = Self.xm4
        #expect(player.vm.dspRowAvailability == .live, "Pure chosen on Bluetooth: Pure declines, Enhanced plays")
        player.vm.selectedDevice = nil
        #expect(player.vm.dspRowAvailability == .live, "no output: nothing would play bit-perfect")
    }
}
