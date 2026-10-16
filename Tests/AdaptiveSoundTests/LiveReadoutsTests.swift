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
import Testing

@MainActor
@Suite("Live readouts: real time, and idle when nobody looks (C-51, C-52)", .serialized)
struct LiveReadoutsTests {
    private static let suiteName = "AdaptiveSoundTests.LiveReadouts"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    /// Let the view model's tasks run: a start, a device read.
    private func settle() async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }

    /// Run the main run loop, where the view model's timers fire, for `seconds`.
    private func runMainLoop(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    /// One frame with every band at `level`.
    private static func frame(_ level: Float) -> [Float] {
        [Float](repeating: level, count: SpectrumConstants.bandCount)
    }

    /// The view model, its engine ready, one song queued and selected.
    private func readyViewModel(_ engine: DeviceTestEngine) async -> AudioViewModel {
        let viewModel = AudioViewModel(defaults: defaults, engine: engine)
        viewModel.initializeEngine()
        await settle()
        let url = URL(fileURLWithPath: "/nonexistent/live-readouts.flac") // never opened
        let song = AudioFile(name: "Song", relativePath: "", absoluteURL: url, format: "FLAC", durationSeconds: 240)
        viewModel.queue = [QueueItem(file: song)]
        viewModel.selectedTrackIndex = 0
        return viewModel
    }

    // MARK: Peak-hold in real time (D57)

    @Test("a peak cap holds 0.6 s, then falls 1.25 of full scale a second, as frames arrive every 100 ms")
    func peakCapsMoveInRealTime() {
        let engine = DeviceTestEngine()
        let viewModel = AudioViewModel(defaults: defaults, engine: engine)
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
        let viewModel = AudioViewModel(defaults: defaults, engine: engine)
        engine.state.withLock { $0.spectrumFrames = [Self.frame(0.5)] }
        let shown = viewModel.spectrum.lens(at: Date(), isPlaying: false, isPure: false, reduceMotion: false)
        #expect(shown.bars.allSatisfy { abs($0 - 0.5) < 1e-6 }, "paused, the lens drew \(shown.bars.prefix(3))…")
    }

    // MARK: Idle (C-52)

    @Test("with no view showing the spectrum nothing reads it, playing or paused")
    func spectrumUnreadWhileHidden() async {
        let engine = DeviceTestEngine()
        let viewModel = await readyViewModel(engine)
        viewModel.playTrack(at: 0)
        await settle()
        #expect(viewModel.isPlaying)
        let before = engine.state.withLock { $0.spectrumReads }
        runMainLoop(0.35)
        let reads = engine.state.withLock { $0.spectrumReads } - before
        #expect(reads == 0, "playing, with no view showing it, the spectrum was read \(reads) times in 0.35 s")
        viewModel.disarmTransportTick()
    }

    @Test("the transport tick runs while a song plays and stops once a pause has settled")
    func transportTickStopsWhenPaused() async {
        let engine = DeviceTestEngine()
        let viewModel = await readyViewModel(engine)
        viewModel.playTrack(at: 0)
        await settle()
        let playingFrom = engine.state.withLock { $0.snapshotReads }
        runMainLoop(0.35)
        #expect(engine.state.withLock { $0.snapshotReads } > playingFrom, "playing, the tick reads the engine")

        viewModel.pause()
        await settle()
        #expect(!viewModel.isPlaying)
        runMainLoop(0.1) // the tick that finds nothing playing is the last
        let pausedFrom = engine.state.withLock { $0.snapshotReads }
        runMainLoop(0.35)
        let reads = engine.state.withLock { $0.snapshotReads } - pausedFrom
        #expect(reads == 0, "paused, the transport tick read the engine \(reads) times in 0.35 s")
        viewModel.disarmTransportTick()
    }

    @Test("paused, the scrubber follows the paused song at once: a scrub moves it, another song zeroes it")
    func pausedScrubberNeedsNoTick() async {
        let engine = DeviceTestEngine()
        let viewModel = await readyViewModel(engine)
        let url = URL(fileURLWithPath: "/nonexistent/live-readouts-2.flac")
        viewModel.queue.append(QueueItem(file: AudioFile(name: "Next", relativePath: "", absoluteURL: url,
                                                         format: "FLAC", durationSeconds: 200)))
        viewModel.duration = 240
        viewModel.playTrack(at: 0)
        await settle()
        viewModel.seek(to: 81)
        viewModel.pause()
        await settle()
        runMainLoop(0.1) // the tick that finds nothing playing is the last
        #expect(viewModel.transportTimer == nil, "paused, the tick sleeps")
        viewModel.seek(to: 120) // a scrub while paused moves the resume point
        #expect(viewModel.playbackPosition == 120)
        viewModel.selectedTrackIndex = 1 // another song selected: the paused place is not its place
        #expect(viewModel.playbackPosition == 0, "the scrubber kept the other song's place")
        viewModel.disarmTransportTick()
    }

    @Test("paused, turning crossfeed on shows in the hero at once")
    func pausedIntentReachesTheHero() async {
        let engine = DeviceTestEngine()
        let headphones = AudioDeviceModel(id: 7, name: "Headphones", sampleRate: 48000, bufferFrameSize: 512,
                                          uid: "hp", modelUID: nil, transportType: 0, type: .builtin,
                                          isHeadphones: true)
        engine.state.withLock {
            $0.devices = [headphones]
            $0.engineDevice = headphones.id
        }
        let viewModel = await readyViewModel(engine)
        #expect(viewModel.transportTimer == nil, "nothing plays: the tick sleeps")
        viewModel.crossfeedEnabled = true
        #expect(viewModel.signalPath.crossfeedStrength == viewModel.crossfeedStrength,
                "the hero's crossfeed chip waits for a tick that never comes")
        viewModel.disarmTransportTick()
    }
}
