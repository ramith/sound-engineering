@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - What the view model does with the engine's answers: launch, a refused pick, the EQ, shutdown

//
// The shipped `AudioViewModel` over `FakeEngine` (`FakePlayer`). The engine-protocol suite these replace
// (`AudioEngineProtocolTests`) called a mock of a mirror protocol and checked the mock's own counters; here
// the engine's answer is the input and the view model's reaction is under test.

@MainActor
@Suite("The real view model's engine lifecycle", .timeLimit(.minutes(3)), .attachingLogTail)
struct EngineLifecycleTests {
    private static let speakers = AudioDeviceModel(
        id: 42, name: "Speakers", sampleRate: 48000, bufferFrameSize: 512,
        uid: "BuiltInSpeakerDevice", modelUID: nil, transportType: 0, type: .builtin, isHeadphones: false
    )
    private static let headphones = AudioDeviceModel(
        id: 56, name: "Headphones", sampleRate: 44100, bufferFrameSize: 256,
        uid: "AA-BB-CC-DD-EE-FF:output", modelUID: nil, transportType: 0, type: .wireless, isHeadphones: true
    )

    /// An engine with both devices, playing on the speakers.
    private static func engineOnSpeakers() -> FakeEngine {
        let engine = FakeEngine()
        engine.state.withLock { state in
            state.devices = [speakers, headphones]
            state.engineDevice = speakers.id
        }
        return engine
    }

    @Test("a launch: the engine comes up, its devices are listed, and the one it plays on shows")
    func aLaunchListsTheDevices() async throws {
        let player = try await FakePlayer.launched(tracks: 0, engine: Self.engineOnSpeakers())
        #expect(player.vm.isEngineReady)
        #expect(player.vm.errorMessage == nil)
        #expect(player.vm.availableDevices.map(\.id) == [Self.speakers.id, Self.headphones.id])
        #expect(player.vm.selectedDevice?.id == Self.speakers.id)
        #expect(player.vm.sampleRate == 48000)
        let initialized = try #require(player.calls.firstIndex(of: .initialize))
        #expect(player.calls[initialized...].contains(.enumerateOutputDevices), "\(player.calls)")
    }

    @Test("a launch with no device listed shows none")
    func aLaunchWithNoDeviceShowsNone() async throws {
        let player = try await FakePlayer.launched(tracks: 0)
        #expect(player.vm.isEngineReady)
        #expect(player.vm.availableDevices.isEmpty)
        #expect(player.vm.selectedDevice == nil)
    }

    @Test("an engine that will not come up leaves the app not ready, says so, and is sent nothing else")
    func anEngineThatWillNotStart() async throws {
        let engine = FakeEngine()
        engine.state.withLock { $0.initializeResult = false }
        let player = try await FakePlayer.launched(tracks: 1, engine: engine)
        #expect(!player.vm.isEngineReady)
        #expect(player.vm.errorMessage == "Failed to initialize audio engine")
        // (The settings the view model restored at init were published before; an engine not yet up
        // ignores them, and gets them again at engine-ready.)
        #expect(player.calls.last == .initialize, "commands after the engine refused to come up: \(player.calls)")
        #expect(player.bench.tickers.isEmpty, "a transport tick ran over an engine that is not up")
        #expect(!player.vm.isInitializing, "the init guard stayed latched: a Retry could never run")
    }

    @Test("an engine that throws as it comes up: the app is not ready and says why")
    func anEngineThatThrowsAtStart() async throws {
        let engine = FakeEngine()
        engine.state.withLock { $0.initializeError = AudioBridgeError.engineNotInitialized }
        let player = try await FakePlayer.launched(tracks: 1, engine: engine)
        #expect(!player.vm.isEngineReady)
        #expect(player.vm.errorMessage?.hasPrefix("Engine initialization failed:") == true,
                "\(player.vm.errorMessage ?? "no error")")
        #expect(!player.vm.isInitializing)
    }

    @Test("a pick the system refuses says so, and the output stays where it was")
    func aRefusedPickSaysSo() async throws {
        let engine = Self.engineOnSpeakers()
        engine.state.withLock { $0.selectResult = false }
        let player = try await FakePlayer.launched(tracks: 0, engine: engine)
        player.vm.selectDevice(Self.headphones)
        try await player.vm.settled()
        #expect(player.vm.errorMessage == "Failed to select device: Headphones")
        #expect(player.vm.selectedDevice?.id == Self.speakers.id)
        #expect(engine.state.withLock(\.picks) == [Self.headphones.id])
        #expect(engine.chosenOutputUID() == nil, "a refused pick became the choice")
    }

    @Test("the EQ goes to the engine as published: its 31 points and whether it plays")
    func theEQGoesToTheEngine() async throws {
        let player = try await FakePlayer.launched(tracks: 0)
        let points = (0 ..< 31).map { Float($0) / 3 - 5 }
        player.vm.publishEQ(points: points, isOn: true, comparing: false)
        player.vm.publishEQ(points: points, isOn: false, comparing: false)
        let published = player.calls.filter { call in
            if case .eq = call {
                return true
            }
            return false
        }
        #expect(published == [.eq(points: points, isOn: true, comparing: false),
                              .eq(points: points, isOn: false, comparing: false)])
    }

    @Test("the EQ's design rate follows the engine's: at launch, and as a tick reads it")
    func theEQDesignRateFollowsTheEngine() async throws {
        let engine = FakeEngine()
        engine.state.withLock { $0.eqDesignRate = 96000 }
        let player = try await FakePlayer.launched(tracks: 2, engine: engine)
        #expect(player.vm.eqDesignRate == 96000)
        try await player.play(at: 0)
        engine.state.withLock { $0.eqDesignRate = 44100 } // the output moved to a 44.1 kHz device
        try player.tick()
        #expect(player.vm.eqDesignRate == 44100)
    }

    @Test("shutdown stops playback before it tears the engine down (P2-C), and the tick stops first")
    func shutdownStopsBeforeTearingDown() async throws {
        let player = try await FakePlayer.launched(tracks: 2)
        try await player.play(at: 0)
        #expect(player.bench.current != nil)
        await player.vm.shutdown()
        #expect(player.bench.current == nil, "the transport tick outlived shutdown")
        #expect(!player.vm.isEngineReady, "a play verb could still reach the engine being torn down")
        let tail = Array(player.calls.suffix(2))
        let epoch = player.vm.transportEpoch
        #expect(tail == [.stop(epoch: epoch, pausing: false), .shutdown], "the last commands: \(tail)")
    }
}
