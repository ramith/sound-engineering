@testable import AdaptiveSound
import AudioDSP
@preconcurrency import AVFoundation
import Foundation
import LevelingKit
import RigKit
import Synchronization
import Testing

// MARK: - The output state the planner plans against, read at one moment (R1.1-B, review S1, N5)

//
// The REAL bridge on offline engines: the output state (M2) is assembled from reads the bridge makes on its queues
// — the graph's rate and widths on `engineQueue` when it is configured for a file, the device boundary at a
// re-establish — and the transport the view model hands over from the main thread. Each fact has one owner, so a
// state built from reads taken at different moments can never write an older fact back over a newer one.

@Suite("The leveling output state, one moment (R1.1-B, S1, N5)", .serialized, .timeLimit(.minutes(3)),
       .attachingLogTail)
struct LevelingOutputStateTests {
    /// A stereo track measured at the engine's rate.
    private static func stereo(_ loudness: Double, peak: Double) -> TrackLevelingDecision {
        TrackLevelingDecision(mode: .leveled, source: .analysis, continuousWithPrevious: false,
                              unfolded: .init(loudness: loudness, truePeak: peak), folded: nil, roles: [1, 2],
                              peakRate: 48000)
    }

    /// Start `url` through the bridge's own start (`playFile`) on `engineQueue`, a new play of `decision`.
    private static func start(_ bridge: AudioEngineBridge, _ url: URL, _ decision: TrackLevelingDecision)
        async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bridge.engineQueue.async {
                do {
                    guard let engine = bridge.avEngineRef, let player = bridge.playerNodeRef else {
                        throw AudioBridgeError.engineNotInitialized
                    }
                    if !engine.isRunning {
                        try engine.start()
                    }
                    bridge.holdStartDecision(LevelingStart(decision: decision, listen: .newPlay), for: url)
                    bridge.setLastFileURL(url)
                    try bridge.playFile(at: url, engine: engine, playerNode: player, startAt: 0)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// `body` on `engineQueue`, waited for.
    private static func onEngineQueue(_ bridge: AudioEngineBridge, _ body: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            bridge.engineQueue.async {
                body()
                continuation.resume()
            }
        }
    }

    @Test("LOS-1: a graph configured with the transport read before the view model's hand-over never writes it back")
    func theTransportHasOneOwner() async throws {
        // Wired → Bluetooth at a device switch: the re-establish's configure read the wired transport, then the
        // view model's hand-over (from main) landed, then the configure's state did. C_work must stay Bluetooth's
        // (−1.28 dBTP), never the wired −0.38 under a −1 dBTP limiter.
        let rig = try await EnhancedTransportRig(path: .passthrough, name: "los-transport")
        let track = try rig.writeTrack([440], named: "los-transport-b", rate: 48000, frames: 0 ..< 96000)
        rig.bridge.levelingTransportChanged(kAudioDeviceTransportTypeBuiltIn)
        try await Self.start(rig.bridge, track, Self.stereo(-14, peak: -1))
        let configured = rig.bridge.leveling.outputState // what a configure assembled, the wired transport in it
        rig.bridge.levelingTransportChanged(kAudioDeviceTransportTypeBluetooth)
        let bluetooth = try #require(rig.bridge.leveling.audiblePlan).workingCeilingDbtp
        rig.bridge.applyOutputState(configured)
        #expect(rig.bridge.leveling.outputState.transportType == kAudioDeviceTransportTypeBluetooth,
                "the configure wrote the wired transport back over the view model's hand-over")
        let ceiling = try #require(rig.bridge.leveling.audiblePlan).workingCeilingDbtp
        #expect(abs(ceiling - bluetooth) < 1e-12, "C_work \(ceiling) dBTP, Bluetooth's is \(bluetooth)")
        await rig.finish()
    }

    @Test("LOS-2: a re-establish while a configure re-widens the graph never mixes the old roles with the new width")
    func aReestablishNeverMixesRolesAndWidth() async throws {
        // A stereo file played; a 5.1 file's start has re-widened the graph to six channels but not yet applied its
        // output state when a device change's re-establish refreshes it. Roles [L R U U U U] at N = 6 would fold C,
        // the LFE and the surrounds at 0.5 into both sides for the whole track.
        let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
        let stereo = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo))
        let first = try MultichannelFixture.write(layout: stereo, rate: 48000, name: "los-stereo")
        defer { try? FileManager.default.removeItem(at: first) }
        try await Self.start(rig.bridge, first, Self.stereo(-20, peak: -6))
        let surround = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A))
        let bridge = rig.bridge
        await Self.onEngineQueue(bridge) { bridge.reconfigureGraph(channelCount: 6, layout: surround) }
        bridge.refreshOutputState()
        let held = bridge.leveling.outputState
        let roles = withUnsafeBytes(of: held.sourceRoles) { Array($0.prefix(Int(held.sourceChannels))) }
        #expect(held.sourceChannels == 2 && roles == [1, 2],
                "the re-establish applied N = \(held.sourceChannels) with roles \(roles): the configure's to apply")

        // The configure finishes: its own state, whole.
        await Self.onEngineQueue(bridge) { bridge.configureGraphForSource(channelCount: 6, channelLayout: surround) }
        let configured = bridge.leveling.outputState
        let surroundRoles = withUnsafeBytes(of: configured.sourceRoles) { Array($0.prefix(6)) }
        #expect(configured.sourceChannels == 6 && surroundRoles == [1, 2, 3, 4, 5, 6])
        await rig.finish()
    }

    @Test("LOS-3: a layout change between songs plans the new song only — the outgoing one is not re-planned (N5)")
    func aLayoutChangeBetweenSongsPlansTheNewSongOnly() async throws {
        let rig = try await EnhancedTransportRig(path: .passthrough, name: "los-between")
        let events = Mutex<[UInt32]>([])
        rig.bridge.setFoldPlanSink { _, _, event in events.withLock { $0.append(event.rawValue) } }
        let surround = try rig.writeTrack([440], named: "los-between-51", rate: 48000, frames: 0 ..< 96000,
                                          channels: 6)
        try await Self.start(rig.bridge, surround, TrackLevelingDecision.off)
        let delivered = events.withLock { $0 }
        #expect(delivered == [AsPlanEventFreshStart.rawValue],
                "the switch to a 5.1 file delivered \(delivered) (3: the outgoing song re-planned protectively)")
        await rig.finish()
    }
}
