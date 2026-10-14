@testable import AdaptiveSound
import Foundation
import Testing

// MARK: - The view model's seek, placed by the one rule (council C-25)

//
// The real `AudioViewModel` over the recording engine: what the scrubber, its keys and Control Center
// send is placed by `SeekTarget.place` before it becomes the playhead, a resume point or an engine
// request. A NaN used to become all three (and trap the engine).

@MainActor
@Suite("AudioViewModel — a seek is placed before it goes anywhere (C-25)")
struct SeekViewModelTests {
    private let engine = DeviceTestEngine()
    private let viewModel: AudioViewModel

    init() throws {
        // A private, empty defaults suite: nothing here touches the app's own.
        let defaults = try #require(UserDefaults(suiteName: "SeekViewModelTests.\(UUID().uuidString)"))
        viewModel = AudioViewModel(defaults: defaults, engine: engine)
        viewModel.isEngineReady = true
        let url = URL(fileURLWithPath: "/nonexistent/song.flac") // never opened: the engine records it
        let song = AudioFile(name: "Song", relativePath: "", absoluteURL: url, format: "FLAC", durationSeconds: 240)
        viewModel.queue = [QueueItem(file: song)]
        viewModel.selectedTrackIndex = 0
        viewModel.duration = 240
        viewModel.isPlaying = true // the engine route
        viewModel.playbackPosition = 30
    }

    /// Let the view model's seek task reach the engine.
    private func settle() async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }

    @Test("not a number: no seek, the playhead stays", arguments: [Double.nan, .infinity, -.infinity])
    func notANumberIsNoSeek(_ target: Double) async {
        viewModel.seek(to: target)
        await settle()
        #expect(viewModel.playbackPosition == 30)
        #expect(engine.state.withLock { $0.seeks }.isEmpty)
    }

    @Test("past the end is the end; before the top is the top")
    func outOfRangeIsPlacedInside() async {
        viewModel.seek(to: 300)
        await settle()
        #expect(viewModel.playbackPosition == 240)
        viewModel.seek(to: -5)
        await settle()
        #expect(viewModel.playbackPosition == 0)
        #expect(engine.state.withLock { $0.seeks } == [240, 0])
    }

    @Test("paused: a non-number never becomes the resume point")
    func pausedNotANumberKeepsTheResumePoint() async {
        viewModel.pause()
        await settle()
        let resumeAt = viewModel.pausedResumePosition
        viewModel.seek(to: .nan)
        #expect(viewModel.pausedResumePosition == resumeAt)
        viewModel.seek(to: 500)
        #expect(viewModel.pausedResumePosition == 240)
    }
}
