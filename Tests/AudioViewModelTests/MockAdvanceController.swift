import Testing

// MARK: - State machine mirror for auto-advance tests

/// Mirrors the continuous-playback state machine from `AudioViewModel`.
/// Only the auto-advance logic (not AVAudioFile duration or timer firing) is
/// mirrored; everything async/effectful is synchronous in this model.
///
/// NOTE: AudioViewModel lives in the `AdaptiveSound` executable target. SPM does
/// not allow @testable import of executable targets, so these tests exercise the
/// auto-advance state machine via this local mirror that replicates the exact
/// logic from AudioViewModel. When AudioViewModel is extracted into a library
/// target, replace this mirror approach with @testable import AdaptiveSoundCore
/// and drive AudioViewModel directly.
final class MockAdvanceController {
    // MARK: Playlist

    var playlist: [String] = [] // track names (stand-ins for AudioFile)
    var selectedTrackIndex: Int?

    // MARK: Playback state

    var isPlaying: Bool = false
    var playbackPosition: Double = 0
    var duration: Double = 0
    var pureModeEnabled: Bool = false
    var errorMessage: String?

    // MARK: Repeat / Shuffle

    var shuffleEnabled: Bool = false
    var repeatMode: Int = 0 // 0=none, 1=all, 2=one

    // MARK: Gapless state

    var pendingNextIndex: Int?
    var lastTransitionCount: UInt64 = 0
    private(set) var startPlaybackCallCount: Int = 0
    private(set) var lastStartedIndex: Int?
    private(set) var lastStartedPureMode: Bool = false
    private(set) var setNextTrackCallCount: Int = 0
    private(set) var lastNextTrackURL: String? // nil = cleared

    // MARK: Simulated engine state

    var engineTransitionCount: UInt64 = 0
    var engineEndedFlag: Bool = false
    var startAudioThrows: Bool = false
    /// Models the async restart window on a Pure rate-transition advance: when `true`, `startPlayback`
    /// only records the call and returns WITHOUT resetting `engineEndedFlag`/`isPlaying`/`pendingNextIndex`
    /// — i.e. the real `pureModeEngineStart` (which resets `ended_`) hasn't run yet. Lets a test fire a
    /// re-entrant tick while "ended" is still true, to prove the advance happens exactly once.
    var deferEndedReset: Bool = false

    // MARK: - Mirror of startPlayback()

    func startPlayback() {
        guard let idx = selectedTrackIndex, idx < playlist.count else {
            errorMessage = "No track selected"
            return
        }
        startPlaybackCallCount += 1
        lastStartedIndex = idx
        lastStartedPureMode = pureModeEnabled

        if startAudioThrows {
            errorMessage = "Playback failed: simulated error"
            isPlaying = false
            pendingNextIndex = nil
            return
        }

        // Async restart in flight (Pure rate-transition advance): the real pureModeEngineStart that
        // resets ended_/isPlaying/pending hasn't run yet — leave state untouched so a re-entrant tick
        // is exercisable. (Normal tests keep this false → synchronous reset, the common case.)
        if deferEndedReset {
            return
        }

        // Reset transition baseline.
        lastTransitionCount = engineTransitionCount
        engineEndedFlag = false

        isPlaying = true
        errorMessage = nil
        playbackPosition = 0

        // Compute and queue the on-deck track.
        let nextIdx = computeNextIndex(current: idx, playlistCount: playlist.count)
        pendingNextIndex = nextIdx
        primeNextTrack(nextIdx)
    }

    private func primeNextTrack(_ idx: Int?) {
        setNextTrackCallCount += 1
        if let validIdx = idx, validIdx < playlist.count {
            lastNextTrackURL = playlist[validIdx]
        } else {
            lastNextTrackURL = nil
        }
    }

    // MARK: - Mirror of tickSpectrum() — gapless poll section

    /// Call this to simulate one 20 Hz tick.  The caller controls `engineTransitionCount`
    /// and `engineEndedFlag` to drive the state machine.
    func tick() {
        guard isPlaying else { return }

        if engineTransitionCount > lastTransitionCount {
            lastTransitionCount = engineTransitionCount
            handleTrackTransition()
        } else if engineEndedFlag {
            // Mirror production: a still-queued track (a Pure rate-transition that couldn't be armed
            // for a seamless seam) advances via a fresh start; pendingNextIndex is cleared
            // SYNCHRONOUSLY before startPlayback to block a re-entrant double-advance. Otherwise stop.
            if let nextIdx = pendingNextIndex, nextIdx < playlist.count {
                selectedTrackIndex = nextIdx
                pendingNextIndex = nil
                startPlayback()
            } else {
                isPlaying = false
                playbackPosition = 0
            }
        }
    }

    // MARK: - Mirror of handleTrackTransition()

    private func handleTrackTransition() {
        guard let nextIdx = pendingNextIndex else { return }
        guard nextIdx < playlist.count else {
            pendingNextIndex = nil
            isPlaying = false
            playbackPosition = 0
            return
        }

        // Advance selection and reset scrubber / duration.
        selectedTrackIndex = nextIdx
        playbackPosition = 0
        duration = 0

        // Compute the NEW next index.
        let newNextIdx = computeNextIndex(current: nextIdx, playlistCount: playlist.count)
        pendingNextIndex = newNextIdx
        primeNextTrack(newNextIdx)
    }

    // MARK: - Mirror of computeNextIndex()

    func computeNextIndex(current: Int, playlistCount: Int) -> Int? {
        guard playlistCount > 0 else { return nil }

        if repeatMode == 2 { return current }

        if shuffleEnabled, playlistCount > 1 {
            // Deterministic in tests: use a simple linear walk that avoids current.
            // (The real VM uses Int.random; we verify the property, not the value.)
            return (current + 1) % playlistCount
        }

        let nextLinear = current + 1
        if nextLinear < playlistCount { return nextLinear }
        if repeatMode == 1 { return 0 }
        return nil
    }

    // MARK: - Mirror of removeTrack(at:) — gapless-relevant section

    /// Select a neighbour index after removing the item at `removed` from a list of `count` items.
    private func neighbourIndex(removed: Int, count: Int) -> Int? {
        if removed < count { return removed }
        if removed > 0 { return removed - 1 }
        return nil
    }

    func removeTrack(at index: Int) {
        guard index >= 0, index < playlist.count else { return }

        let removingCurrent = (selectedTrackIndex == index)
        playlist.remove(at: index)

        if let pending = pendingNextIndex {
            if pending == index {
                // On-deck track removed: re-compute from the still-playing current track.
                // P2-2: playlist.remove(at:) has already shifted indices — if selectedTrackIndex
                // was after the removed slot, the correct post-removal index is one lower.
                let rawCurrent = selectedTrackIndex ?? 0
                let currentIdx = rawCurrent > index ? rawCurrent - 1 : rawCurrent
                let newNextIdx = computeNextIndex(current: currentIdx, playlistCount: playlist.count)
                pendingNextIndex = newNextIdx
                setNextTrackCallCount += 1
                lastNextTrackURL = newNextIdx.map { playlist[$0] }
            } else if pending > index {
                pendingNextIndex = pending - 1
            }
        }

        if removingCurrent, isPlaying {
            pendingNextIndex = nil
            isPlaying = false
            playbackPosition = 0
            selectedTrackIndex = neighbourIndex(removed: index, count: playlist.count)
            return
        }

        if selectedTrackIndex == index {
            selectedTrackIndex = neighbourIndex(removed: index, count: playlist.count)
        } else if let cur = selectedTrackIndex, cur > index {
            selectedTrackIndex = cur - 1
        }
    }

    // MARK: - Mirror of clearPlaylist()

    func clearPlaylist() {
        playlist.removeAll()
        selectedTrackIndex = nil
        pendingNextIndex = nil
        isPlaying = false
        playbackPosition = 0
        duration = 0
    }

    // MARK: - Mirror of stopPlayback()

    func stopPlayback() {
        pendingNextIndex = nil
        isPlaying = false
        playbackPosition = 0
        duration = 0
    }

    // MARK: - Mirror of playTrack(at:)

    func playTrack(at index: Int) {
        guard index < playlist.count else { return }
        selectedTrackIndex = index
        startPlayback()
    }
}

// MARK: - Test helpers

func makeTracks(count: Int) -> [String] {
    (0 ..< count).map { "track\($0).flac" }
}

func makeURL(_ name: String) -> String {
    name
}
