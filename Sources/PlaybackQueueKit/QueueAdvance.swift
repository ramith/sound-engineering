// PlaybackQueueKit — the pure, testable queue/advance decision core (S9-Q1).
//
// Extracted from `AudioViewModel` so the advance logic is exercised by tests against
// the REAL code. `AudioViewModel` lives in the `AdaptiveSound` EXECUTABLE target,
// which SPM cannot `@testable import`, so its next/previous-index logic was previously
// re-implemented in a hand-mirror (`MockAdvanceController`) that could silently drift.
// Moving the decision core into this library target lets both the app AND the tests
// import the identical implementation.
//
// Pure + `Sendable`: no `@MainActor`, no engine, no VM state. The shuffle choice is an
// INJECTED picker — production passes `uniformRandomExcluding` (a uniform random index
// ≠ current); tests pass a deterministic stand-in. That injection is what finally makes
// the shuffle branch deterministically testable against the real logic (the mirror had
// to fork a deterministic copy precisely because the production code called `Int.random`
// inline).

/// The pure next/previous-index decision for continuous playback. `repeatMode` is
/// 0 = none, 1 = all, 2 = one (matching `AudioViewModel.repeatMode`).
public enum QueueAdvance {
    /// The index to play AFTER `current` in a queue of `count` tracks, honouring
    /// `shuffle` + `repeatMode`. `manualSkip` is `true` when the user pressed Next
    /// (under repeat-one a manual skip STEPS to the next track; an automatic advance
    /// repeats the current one). `randomPick(current, count)` supplies the shuffle
    /// choice (called only when `shuffle && count > 1`). Returns `nil` when playback
    /// should stop / stay after `current`.
    public static func nextIndex(
        current: Int,
        count: Int,
        shuffle: Bool,
        repeatMode: Int,
        manualSkip: Bool = false,
        randomPick: (Int, Int) -> Int
    ) -> Int? {
        guard count > 0 else { return nil }
        if repeatMode == 2, !manualSkip { return current } // repeat-one: auto repeats, manual steps
        if shuffle, count > 1 { return randomPick(current, count) }
        let nextLinear = current + 1
        if nextLinear < count { return nextLinear }
        return repeatMode == 1 ? 0 : nil // repeat-all wraps to the first track; else stop
    }

    /// The index to play BEFORE `current` (the Previous button). Shuffle → `randomPick`
    /// (a different track; no shuffle history is kept); repeat-all wraps to the last
    /// track; otherwise steps back, returning `nil` at the first track. Previous is
    /// always a manual action, so repeat-one steps back rather than repeating.
    public static func previousIndex(
        current: Int,
        count: Int,
        shuffle: Bool,
        repeatMode: Int,
        randomPick: (Int, Int) -> Int
    ) -> Int? {
        guard count > 0 else { return nil }
        if shuffle, count > 1 { return randomPick(current, count) }
        let prevLinear = current - 1
        if prevLinear >= 0 { return prevLinear }
        return repeatMode == 1 ? count - 1 : nil // repeat-all wraps to the last track
    }

    /// The on-deck index to arm after appending to a PLAYING queue, or `nil` to leave the
    /// current on-deck pick untouched. Only the linear end-of-queue case re-arms: playing
    /// the last track (`current == oldCount - 1`) with nothing on-deck (`!hasPending`),
    /// repeat-off, not shuffle → the FIRST appended track (index `oldCount`) becomes the
    /// immediate next. Every other case (shuffle, mid-list, repeat-all/one, already-armed)
    /// returns `nil` — appending must NEVER re-roll or disturb an existing primed pick
    /// (design §6). The pure decision behind `appendToQueue`, shared by the app + tests.
    public static func appendArmIndex(
        current: Int, oldCount: Int, hasPending: Bool, shuffle: Bool, repeatMode: Int
    ) -> Int? {
        guard !hasPending, !shuffle, repeatMode == 0, current == oldCount - 1 else { return nil }
        return oldCount
    }

    /// The production shuffle picker: a uniformly-random index in `0 ..< count` that is
    /// not `current`. Precondition: `count > 1` (guarded by the `shuffle && count > 1`
    /// branch in `nextIndex`/`previousIndex`). Rejection-free + O(1): pick among the
    /// `count - 1` other slots, then skip over `current`. On misuse (`count <= 1`) the
    /// empty `Range` **traps** — a fast, diagnosable failure rather than an infinite loop.
    public static func uniformRandomExcluding(_ current: Int, _ count: Int) -> Int {
        let pick = Int.random(in: 0 ..< (count - 1))
        return pick < current ? pick : pick + 1
    }
}
