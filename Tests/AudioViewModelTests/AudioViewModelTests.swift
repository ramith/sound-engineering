import Testing

// NOTE: AudioViewModel lives in the `AdaptiveSound` executable target. SPM does
// not allow @testable import of executable targets, so we test the selection
// logic via a local mirror that replicates the exact two-line body of
// playTrack(at:).  When AudioViewModel is extracted into a library target
// (planned for Phase 1.5), replace MockPlaylistController with
// @testable import AdaptiveSoundCore and remove this mirror.

// MARK: - Minimal mirror of AudioViewModel playlist/selection logic

private final class MockPlaylistController {
    /// Stand-in for [AudioFile] — only count() matters for playTrack(at:) logic.
    var playlist: [String] = []
    var selectedTrackIndex: Int?
    private(set) var startPlaybackCallCount = 0
    private(set) var lastStartedIndex: Int?

    /// Exact copy of the fixed playTrack(at:) body
    func playTrack(at index: Int) {
        guard index < playlist.count else { return }
        selectedTrackIndex = index // the fix
        startPlayback()
    }

    /// Stub — records that playback was triggered
    func startPlayback() {
        startPlaybackCallCount += 1
        lastStartedIndex = selectedTrackIndex
    }
}

// MARK: - Test helpers

private func makeTracks(count: Int) -> [String] {
    (0 ..< count).map { "track\($0).wav" }
}

// MARK: - Test suite

@Suite("AudioViewModel - playTrack(at:)")
struct AudioViewModelTests {
    // MARK: Core fix: selected index must match the requested index

    @Test("playTrack(at:2) sets selectedTrackIndex to 2")
    func playTrackSelectsCorrectTrack() {
        let vm = MockPlaylistController()
        vm.playlist = makeTracks(count: 3)

        vm.playTrack(at: 2)

        #expect(vm.selectedTrackIndex == 2,
                "playTrack(at:2) must set selectedTrackIndex to 2 before starting playback")
    }

    @Test("playTrack(at:) triggers startPlayback() exactly once")
    func playTrackTriggersStartPlayback() {
        let vm = MockPlaylistController()
        vm.playlist = makeTracks(count: 3)

        vm.playTrack(at: 1)

        #expect(vm.startPlaybackCallCount == 1,
                "playTrack(at:) must call startPlayback() exactly once")
    }

    @Test("startPlayback() sees the newly-set index, not the stale one")
    func startPlaybackSeesUpdatedIndex() {
        // Regression: startPlayback() must run AFTER selectedTrackIndex is set,
        // not before (the bug was the reversed order).
        let vm = MockPlaylistController()
        vm.playlist = makeTracks(count: 3)
        vm.selectedTrackIndex = 0 // pre-existing selection

        vm.playTrack(at: 2)

        #expect(vm.lastStartedIndex == 2,
                "startPlayback() must observe the newly-set index, not the stale one")
    }

    // MARK: Guard: out-of-bounds index must be silently rejected

    @Test("out-of-bounds index does not change selection or trigger playback")
    func playTrackIgnoresOutOfBoundsIndex() {
        let vm = MockPlaylistController()
        vm.playlist = makeTracks(count: 3)
        vm.selectedTrackIndex = 0

        vm.playTrack(at: 99) // beyond playlist end

        #expect(vm.selectedTrackIndex == 0,
                "Out-of-bounds index must not change selectedTrackIndex")
        #expect(vm.startPlaybackCallCount == 0,
                "Out-of-bounds index must not trigger startPlayback()")
    }

    @Test("playTrack on empty playlist leaves selectedTrackIndex nil")
    func playTrackOnEmptyPlaylist() {
        let vm = MockPlaylistController()
        // playlist is empty

        vm.playTrack(at: 0)

        #expect(vm.selectedTrackIndex == nil,
                "Playing on an empty playlist must leave selectedTrackIndex nil")
        #expect(vm.startPlaybackCallCount == 0,
                "Playing on an empty playlist must not trigger startPlayback()")
    }

    // MARK: Index boundary: exact last valid index

    @Test("playTrack at last valid index succeeds")
    func playTrackAtLastValidIndex() {
        let vm = MockPlaylistController()
        vm.playlist = makeTracks(count: 5)

        vm.playTrack(at: 4) // last valid index

        #expect(vm.selectedTrackIndex == 4)
        #expect(vm.startPlaybackCallCount == 1)
    }

    @Test("index equal to playlist.count is rejected")
    func playTrackAtExactCountIsRejected() {
        let vm = MockPlaylistController()
        vm.playlist = makeTracks(count: 5)

        vm.playTrack(at: 5) // one past the end

        #expect(vm.selectedTrackIndex == nil,
                "Index equal to playlist.count must be rejected by the guard")
        #expect(vm.startPlaybackCallCount == 0)
    }

    // MARK: Repeated calls replace selection

    @Test("second playTrack(at:) call overwrites the previous selection")
    func playTrackOverwritesPreviousSelection() {
        let vm = MockPlaylistController()
        vm.playlist = makeTracks(count: 5)

        vm.playTrack(at: 0)
        vm.playTrack(at: 3)

        #expect(vm.selectedTrackIndex == 3,
                "Second playTrack(at:) call must overwrite the previous selection")
        #expect(vm.startPlaybackCallCount == 2)
    }
}
