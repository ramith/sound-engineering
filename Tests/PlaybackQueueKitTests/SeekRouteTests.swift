import PlaybackQueueKit
import Testing

// MARK: - SeekRoute — what a seek does while playing, paused or stopped (VM-SR)

//
// Imports the shipped `PlaybackQueueKit` target, so the routing `AudioViewModel.seek(to:)` runs is the
// routing under test (the footer scrubber, its keys and Control Center all seek through it).

@Suite("PlaybackQueueKit — SeekRoute, where a seek goes (VM-SR)")
struct SeekRouteTests {
    @Test("VM-SR-01: a seek while playing drives the engine")
    func playingSeeksTheEngine() {
        #expect(SeekRoute.route(isPlaying: true, isPaused: false) == .engine)
    }

    @Test("VM-SR-02: a seek while paused moves only the resume point — the engine is never touched")
    func pausedMovesTheResumePoint() {
        #expect(SeekRoute.route(isPlaying: false, isPaused: true) == .resumePoint)
    }

    @Test("VM-SR-03: a scrub between Pause and the engine stopping belongs to the pause")
    func pausingWinsOverTheLateIsPlaying() {
        // pause() records the resume point at once; isPlaying drops only when the engine has stopped.
        #expect(SeekRoute.route(isPlaying: true, isPaused: true) == .resumePoint)
    }

    @Test("VM-SR-04: a seek while stopped (Stop, or the queue ended) does nothing")
    func stoppedIgnoresTheSeek() {
        #expect(SeekRoute.route(isPlaying: false, isPaused: false) == .ignore)
    }
}
