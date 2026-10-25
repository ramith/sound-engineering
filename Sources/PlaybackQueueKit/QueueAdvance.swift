// PlaybackQueueKit — the pure, testable queue/advance decision core (S9-Q1).
//
// Extracted from `AudioViewModel` so the advance logic is exercised by tests against
// the REAL code. `AudioViewModel` lives in the `AdaptiveSound` EXECUTABLE target,
// which SPM cannot `@testable import`, so its next/previous-index logic was previously
// re-implemented in a hand-mirror (`MockAdvanceController`, since deleted) that could silently drift.
// Moving the decision core into this library target lets both the app AND the tests
// import the identical implementation.
//
// Pure + `Sendable`: no `@MainActor`, no engine, no VM state. The queue's OWN order only: shuffle is a
// `ShufflePass` (R1.1-B, council C-16), and `PlaybackOrder` chooses between the two.

/// The pure next/previous-index decision for continuous playback in the queue's own order. `repeatMode`
/// is 0 = none, 1 = all, 2 = one (matching `AudioViewModel.repeatMode`).
public enum QueueAdvance {
    /// The index to play AFTER `current` in a queue of `count` tracks, honouring `repeatMode`.
    /// `manualSkip` is `true` when the user pressed Next (under repeat-one a manual skip STEPS to the
    /// next track; an automatic advance repeats the current one). Returns `nil` when playback should
    /// stop / stay after `current`.
    public static func nextIndex(current: Int, count: Int, repeatMode: Int, manualSkip: Bool = false) -> Int? {
        guard count > 0 else { return nil }
        if repeatMode == 2, !manualSkip {
            return current
        } // repeat-one: auto repeats, manual steps
        let nextLinear = current + 1
        if nextLinear < count {
            return nextLinear
        }
        return repeatMode == 1 ? 0 : nil // repeat-all wraps to the first track; else stop
    }

    /// The index to play BEFORE `current` (the Previous button): repeat-all wraps to the last track;
    /// otherwise steps back, returning `nil` at the first track. Previous is always a manual action, so
    /// repeat-one steps back rather than repeating.
    public static func previousIndex(current: Int, count: Int, repeatMode: Int) -> Int? {
        guard count > 0 else { return nil }
        let prevLinear = current - 1
        if prevLinear >= 0 {
            return prevLinear
        }
        return repeatMode == 1 ? count - 1 : nil // repeat-all wraps to the last track
    }
}
