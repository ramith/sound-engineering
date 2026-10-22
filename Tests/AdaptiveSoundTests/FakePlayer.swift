@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - The real view model over FakeEngine, launched as the app launches it

/// The shipped `AudioViewModel` over `FakeEngine`: launched through `initializeEngine` as at app start,
/// its transport tick fired by hand (`TickerBench`), a defaults suite of its own. For what the view model
/// does with what the engine reports or answers — a transport sample, a lost device, a refused call —
/// where `Rig` (the on-deck model) is for what plays next. The engine is the double: what it reports is
/// what the test sets, never a behaviour of its own.
@MainActor
struct FakePlayer {
    let vm: AudioViewModel
    let engine: FakeEngine
    /// The view model's transport tick: it runs while a song plays or a command is on its way.
    let bench = TickerBench()
    /// This player's defaults suite, its own and removed with it.
    private let world = IsolatedDefaults("FakePlayer")

    /// `tracks` songs queued, nothing selected, the engine not started yet.
    init(tracks: Int, engine: FakeEngine = FakeEngine()) {
        QuietLog.install()
        self.engine = engine
        vm = AudioViewModel(defaults: world.defaults, engine: engine, makeTicker: bench.maker)
        vm.queue = (0 ..< tracks).map { QueueItem(file: audioFile($0)) }
    }

    /// Launched: the engine was asked to come up (it did, or the view model took in why not), and
    /// everything the launch set going has finished.
    static func launched(tracks: Int, engine: FakeEngine = FakeEngine()) async throws -> FakePlayer {
        let player = FakePlayer(tracks: tracks, engine: engine)
        player.vm.initializeEngine()
        try await player.vm.settled()
        return player
    }

    /// Play the song at `index` and wait until it plays: its start and its on-deck request landed.
    func play(at index: Int) async throws {
        vm.playTrack(at: index)
        try await vm.settled()
        try await until("the song to play") { vm.isPlaying && vm.transportCommand == nil }
    }

    /// The engine's clock samples the transport of the newest request the view model made.
    func engineReports(position: Double?, transitionCount: UInt64 = 0, ended: Bool = false) {
        let sample = TransportSnapshot(epoch: vm.transportEpoch, position: position, transitionCount: transitionCount,
                                       ended: ended)
        engine.state.withLock { $0.transport = sample }
    }

    /// One tick of the transport, as its 20 Hz timer delivers it. There must be a tick going.
    func tick(sourceLocation: SourceLocation = #_sourceLocation) throws {
        try #require(bench.current, "no transport tick is going", sourceLocation: sourceLocation).fire()
    }

    /// The commands the engine has been sent so far.
    var calls: [FakeEngine.Call] {
        engine.state.withLock(\.calls)
    }
}
