// R1.1-A (council C-51 D57, C-52; KI-UI-02): live readouts move in real time and cost nothing while
// nothing plays or shows them. On the real `AudioViewModel` over a recording engine.
//
// - The peak caps hold 0.6 s, then fall 1.25 of full scale a second — in real time. Frames arrive
//   once per tap buffer (100 ms); before R1.1 each frame advanced the caps by a nominal 1/20 s, so
//   they held 1.2 s and fell at half speed.
// - With no view showing the spectrum, nothing reads it; once a pause has settled, the transport
//   tick stops too. Before R1.1 two 20 Hz main-thread timers ran from engine-ready to quit. With the
//   tick asleep, what it used to carry while paused still reaches the screen at once: the scrubber
//   when the paused song changes, the hero's crossfeed chip when crossfeed is turned on.

@testable import AdaptiveSound
import Foundation
import RigKit
import Testing

@MainActor
@Suite("Live readouts: real time, and idle when nobody looks (C-51, C-52)", .timeLimit(.minutes(3)),
       .attachingLogTail)
struct LiveReadoutsTests {
    /// The suite of this test's own, removed with it.
    private let world = IsolatedDefaults("LiveReadouts")
    /// The transport tick's hand-fired tickers: a tick happens when the test says so.
    private let bench = TickerBench()

    init() {
        QuietLog.install()
    }

    /// Whether a start or a pause has landed: nothing is on its way to the engine.
    private func landed(_ viewModel: AudioViewModel, playing: Bool) -> Bool {
        viewModel.isPlaying == playing && viewModel.transportCommand == nil
    }

    /// One frame with every band at `level`.
    private static func frame(_ level: Float) -> [Float] {
        [Float](repeating: level, count: SpectrumConstants.bandCount)
    }

    /// The view model, its engine ready, one song queued and selected.
    private func readyViewModel(_ engine: DeviceTestEngine) async throws -> AudioViewModel {
        let viewModel = AudioViewModel(defaults: world.defaults, engine: engine, makeTicker: bench.maker)
        viewModel.initializeEngine()
        try await until("the engine to come up") { viewModel.isEngineReady || viewModel.errorMessage != nil }
        #expect(viewModel.isEngineReady, "the engine did not come up: \(viewModel.errorMessage ?? "")")
        let url = URL(fileURLWithPath: "/nonexistent/live-readouts.flac") // never opened
        let song = AudioFile(name: "Song", relativePath: "", absoluteURL: url, format: "FLAC", durationSeconds: 240)
        viewModel.queue = [QueueItem(file: song)]
        viewModel.selectedTrackIndex = 0
        return viewModel
    }

    /// Start the song and wait until it plays — and the tick, which a start arms, is going.
    private func startPlaying(_ viewModel: AudioViewModel) async throws -> ManualTicker {
        viewModel.playTrack(at: 0)
        try await until("the song to start") { landed(viewModel, playing: true) && bench.current != nil }
        return try #require(bench.current)
    }

    /// Let a pause land, then deliver the tick that finds nothing playing and nothing on its way: the last.
    private func pauseAndFinishTheLastTick(_ viewModel: AudioViewModel, _ ticker: ManualTicker) async throws {
        viewModel.pause()
        try await until("the pause to land") { landed(viewModel, playing: false) }
        ticker.fire()
    }

    // MARK: Peak-hold in real time (D57)

    @Test("a peak cap holds 0.6 s, then falls 1.25 of full scale a second, as frames arrive every 100 ms")
    func peakCapsMoveInRealTime() {
        let engine = DeviceTestEngine()
        let viewModel = AudioViewModel(defaults: world.defaults, engine: engine, makeTicker: bench.maker)
        let sampler = viewModel.spectrum
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let bar = SpectrumConstants.displayBarCount / 2
        func cap(at seconds: Double, playing: Bool = true) -> Float {
            sampler.lens(at: start.addingTimeInterval(seconds), isPlaying: playing, isPure: false,
                         reduceMotion: false).caps[bar]
        }
        // A full-scale frame, then silence: one frame per 100 ms tap buffer, for one second. The bar
        // reaches the top at 0.1 s (its ease is 80 ms) and the cap latches there.
        engine.state.withLock { $0.spectrumFrames = [Self.frame(1)] + Array(repeating: Self.frame(0), count: 10) }
        for step in 0 ... 10 {
            _ = cap(at: Double(step) / 10)
        }
        // 1.0 s after it latched: held 0.6 s, then fell 1.25 × 0.4 = 0.5.
        let fallen = cap(at: 1.1)
        #expect(abs(fallen - 0.5) < 0.02, "one second after a full-scale peak the cap stands at \(fallen), not 0.5")
        // Paused, nothing is fed: the cap freezes, and the pause is not counted when play resumes.
        #expect(cap(at: 3.0, playing: false) == fallen, "paused, the cap moved")
        #expect(cap(at: 5.0) == fallen, "the pause was counted as time played")
        let resumed = cap(at: 5.2)
        #expect(abs(resumed - (fallen - 0.25)) < 0.02, "0.2 s after resuming the cap stands at \(resumed)")
    }

    @Test("paused, the lens shows the latest frame as it is: it draws once, so never part-way through an ease")
    func pausedLensShowsTheLatestFrame() {
        let engine = DeviceTestEngine()
        let viewModel = AudioViewModel(defaults: world.defaults, engine: engine, makeTicker: bench.maker)
        engine.state.withLock { $0.spectrumFrames = [Self.frame(0.5)] }
        let shown = viewModel.spectrum.lens(at: Date(), isPlaying: false, isPure: false, reduceMotion: false)
        #expect(shown.bars.allSatisfy { abs($0 - 0.5) < 1e-6 }, "paused, the lens drew \(shown.bars.prefix(3))…")
    }

    // MARK: Idle (C-52)

    @Test("with no view showing the spectrum nothing reads it, playing or paused")
    func spectrumUnreadWhileHidden() async throws {
        let engine = DeviceTestEngine()
        let viewModel = try await readyViewModel(engine)
        let ticker = try await startPlaying(viewModel)
        let spectrumBefore = engine.state.withLock { $0.spectrumReads }
        let ticksBefore = engine.state.withLock { $0.snapshotReads }
        // Seven ticks of the transport (0.35 s of playing): each reads the engine's snapshot — the witness
        // that the tick had its chance to read the spectrum — and none reads the spectrum.
        for _ in 0 ..< 7 {
            ticker.fire()
        }
        let ticks = engine.state.withLock { $0.snapshotReads } - ticksBefore
        let reads = engine.state.withLock { $0.spectrumReads } - spectrumBefore
        #expect(ticks == 7, "the seven ticks read the engine \(ticks) times")
        #expect(reads == 0, "playing, with no view showing it, the spectrum was read \(reads) times in seven ticks")
        viewModel.disarmTransportTick()
    }

    @Test("the transport tick runs while a song plays and stops once a pause has settled")
    func transportTickStopsWhenPaused() async throws {
        let engine = DeviceTestEngine()
        let viewModel = try await readyViewModel(engine)
        let ticker = try await startPlaying(viewModel)
        let playingFrom = engine.state.withLock { $0.snapshotReads }
        ticker.fire()
        #expect(engine.state.withLock { $0.snapshotReads } > playingFrom, "playing, the tick reads the engine")
        #expect(ticker.isRunning, "playing, the tick goes on")

        // The tick that finds nothing playing and nothing on its way is the last: it stops itself, so
        // no tick can read the engine from here on.
        try await pauseAndFinishTheLastTick(viewModel, ticker)
        #expect(!ticker.isRunning, "paused, the tick did not stop")
        #expect(viewModel.transportTicker == nil, "paused, the view model still holds its ticker")
        let pausedFrom = engine.state.withLock { $0.snapshotReads }
        ticker.fire() // a stopped ticker delivers nothing
        let reads = engine.state.withLock { $0.snapshotReads } - pausedFrom
        #expect(reads == 0, "paused, the transport tick read the engine \(reads) times")
        viewModel.disarmTransportTick()
    }

    @Test("a play after a pause starts a tick again")
    func playAfterPauseTicksAgain() async throws {
        let engine = DeviceTestEngine()
        let viewModel = try await readyViewModel(engine)
        let first = try await startPlaying(viewModel)
        try await pauseAndFinishTheLastTick(viewModel, first)
        #expect(bench.current == nil, "paused: no tick is going")
        viewModel.play()
        try await until("the play to land, and a tick to start") {
            landed(viewModel, playing: true) && bench.current != nil
        }
        let second = try #require(bench.current)
        #expect(second !== first, "the new tick is a ticker of its own")
        viewModel.disarmTransportTick()
    }

    @Test("the product's ticker is a main-run-loop timer: it fires, and stopping it ends it")
    func runLoopTickerFiresAndStops() async throws {
        var fired = 0
        let ticker = RunLoopTicker(interval: 0.01) { fired += 1 }
        try await untilOnMainRunLoop("the timer to fire three times") { fired >= 3 }
        ticker.stop()
        #expect(!ticker.timer.isValid, "a stopped ticker's timer is still scheduled")
    }

    @Test("paused, the scrubber follows the paused song at once: a scrub moves it, another song zeroes it")
    func pausedScrubberNeedsNoTick() async throws {
        let engine = DeviceTestEngine()
        let viewModel = try await readyViewModel(engine)
        let url = URL(fileURLWithPath: "/nonexistent/live-readouts-2.flac")
        viewModel.queue.append(QueueItem(file: AudioFile(name: "Next", relativePath: "", absoluteURL: url,
                                                         format: "FLAC", durationSeconds: 200)))
        viewModel.duration = 240
        let ticker = try await startPlaying(viewModel)
        viewModel.seek(to: 81)
        try await pauseAndFinishTheLastTick(viewModel, ticker)
        #expect(viewModel.transportTicker == nil, "paused, the tick sleeps")
        viewModel.seek(to: 120) // a scrub while paused moves the resume point
        #expect(viewModel.playbackPosition == 120)
        viewModel.selectedTrackIndex = 1 // another song selected: the paused place is not its place
        #expect(viewModel.playbackPosition == 0, "the scrubber kept the other song's place")
        viewModel.disarmTransportTick()
    }

    @Test("paused, turning crossfeed on shows in the hero at once")
    func pausedIntentReachesTheHero() async throws {
        let engine = DeviceTestEngine()
        let headphones = AudioDeviceModel(id: 7, name: "Headphones", sampleRate: 48000, bufferFrameSize: 512,
                                          uid: "hp", modelUID: nil, transportType: 0, type: .builtin,
                                          isHeadphones: true)
        engine.state.withLock {
            $0.devices = [headphones]
            $0.engineDevice = headphones.id
        }
        let viewModel = try await readyViewModel(engine)
        #expect(viewModel.transportTicker == nil, "nothing plays: the tick sleeps")
        viewModel.crossfeedEnabled = true
        #expect(viewModel.signalPath.crossfeedStrength == viewModel.crossfeedStrength,
                "the hero's crossfeed chip waits for a tick that never comes")
        viewModel.disarmTransportTick()
    }
}
