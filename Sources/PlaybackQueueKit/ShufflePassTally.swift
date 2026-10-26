// PlaybackQueueKit — what a shuffle pass's edits move, counted for a test (R1.1-B, review S3).
//
// A pass's edits run on the main actor, inside the queue's didSet: an Add to Queue, a Play Next, the launch's
// join. Done one song at a time they cost a shift of the whole line per song — about 10⁸ slot moves for a
// 20,000-song Add to Queue. A test proves an edit is linear by counting what it moved, never by a clock
// (testing.md, rule 2): it holds a tally while the edit runs, and the pass's three line writers — insert,
// remove, and `follow`'s one-pass build — add what they wrote or shifted to it.

import Synchronization

/// The slots a shuffle pass's edits wrote or shifted on its line while a test held this tally. The app
/// holds none, so nothing is counted there.
public final class ShufflePassTally: Sendable {
    /// The tally the running task holds, if any: `ShufflePassTally.$current.withValue(tally) { … }`. A task
    /// started inside inherits it.
    @TaskLocal public static var current: ShufflePassTally?

    private let moved = Mutex(0)

    public init() {}

    /// Slots written or shifted so far.
    public var slotsMoved: Int {
        moved.withLock { $0 }
    }

    /// `slots` more were written or shifted.
    func add(_ slots: Int) {
        moved.withLock { $0 += slots }
    }
}
