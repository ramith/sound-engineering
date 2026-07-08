import PlaybackQueueKit
import Testing

// MARK: - State machine mirror for auto-advance tests

/// Mirrors the continuous-playback state machine from `AudioViewModel`.
/// Only the auto-advance logic (not AVAudioFile duration or timer firing) is
/// mirrored; everything async/effectful is synchronous in this model.
///
/// NOTE: AudioViewModel lives in the `AdaptiveSound` executable target, which SPM
/// cannot @testable import. The pure DECISION core (next/previous index) has been
/// extracted to the `PlaybackQueueKit` library (S9-Q1); `computeNextIndex`/
/// `computePreviousIndex` below now DELEGATE to it (no replicated branch logic —
/// QueueAdvanceTests gates the real core directly). What remains mirrored here is only
/// the state-machine SEQUENCING (startPlayback/tick/handleTrackTransition/removeTrack),
/// which is VM+engine-coupled and can't move to a pure library.
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

    // MARK: - Decision core: DELEGATES to the real PlaybackQueueKit.QueueAdvance

    /// A deterministic shuffle picker — a linear walk that avoids `current` — so the
    /// state-machine tests stay deterministic while exercising the REAL decision logic.
    /// (Production injects `QueueAdvance.uniformRandomExcluding`; the shuffle tests
    /// assert the PROPERTY "≠ current, in range", satisfied by both.)
    static let deterministicPick: @Sendable (Int, Int) -> Int = { current, count in (current + 1) % count }

    func computeNextIndex(current: Int, playlistCount: Int, manualSkip: Bool = false) -> Int? {
        QueueAdvance.nextIndex(
            current: current, count: playlistCount, shuffle: shuffleEnabled,
            repeatMode: repeatMode, manualSkip: manualSkip, randomPick: Self.deterministicPick
        )
    }

    func computePreviousIndex(current: Int, playlistCount: Int) -> Int? {
        QueueAdvance.previousIndex(
            current: current, count: playlistCount, shuffle: shuffleEnabled,
            repeatMode: repeatMode, randomPick: Self.deterministicPick
        )
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

    // MARK: - Mirror of the S9-Q2 queue ops (playNow / playNext / appendToQueue)

    //
    // Sequencing scaffold (array + on-deck arming) mirroring AudioViewModel+Queue; the one
    // real DECISION — whether an append re-arms — is the shipped `QueueAdvance.appendArmIndex`
    // (not re-implemented here), so that logic is gated against real code.

    func playNow(_ tracks: [String], startAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        let start = min(max(0, index), tracks.count - 1)
        playlist = tracks
        playTrack(at: start)
    }

    @discardableResult
    func playNext(_ tracks: [String]) -> Int {
        let tracks = dedupedAgainstQueue(tracks)
        guard !tracks.isEmpty else { return 0 }
        guard let current = selectedTrackIndex else { return appendToQueue(tracks) }
        let insertAt = min(current + 1, playlist.count)
        playlist.insert(contentsOf: tracks, at: insertAt)
        if isPlaying { armOnDeck(insertAt) }
        return tracks.count
    }

    @discardableResult
    func appendToQueue(_ tracks: [String]) -> Int {
        let tracks = dedupedAgainstQueue(tracks)
        guard !tracks.isEmpty else { return 0 }
        let oldCount = playlist.count
        playlist.append(contentsOf: tracks)
        guard isPlaying, let current = selectedTrackIndex else { return tracks.count }
        if let armIndex = QueueAdvance.appendArmIndex(
            current: current, oldCount: oldCount, hasPending: pendingNextIndex != nil,
            shuffle: shuffleEnabled, repeatMode: repeatMode
        ) {
            armOnDeck(armIndex)
        }
        return tracks.count
    }

    private func dedupedAgainstQueue(_ tracks: [String]) -> [String] {
        var seen = Set(playlist)
        return tracks.filter { seen.insert($0).inserted }
    }

    /// Mirror of `AudioViewModel.armOnDeck`: set `pendingNextIndex` + record the primed
    /// URL, without `computeNextIndex` or a `lastTransitionCount` touch.
    private func armOnDeck(_ index: Int?) {
        pendingNextIndex = index
        setNextTrackCallCount += 1
        lastNextTrackURL = index.flatMap { $0 < playlist.count ? playlist[$0] : nil }
    }
}

// MARK: - Test helpers

func makeTracks(count: Int) -> [String] {
    (0 ..< count).map { "track\($0).flac" }
}

func makeURL(_ name: String) -> String {
    name
}
