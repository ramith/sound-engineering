// PlaybackQueueKit — what the transport tick reads from the engine (S10.8 G, the disconnect freeze).
//
// The view model's 20 Hz transport tick runs on the main thread. It used to ask the engine live —
// the player node for its playhead, the resampler queue for the seam count — and when macOS held
// the dying output device's lock for seven seconds, those reads waited on it, and so did the whole
// app (founder repro, 2026-10-13). Now the engine samples those facts off the main thread and
// publishes a copy; the tick reads the copy. A copy holds no Apple object, and reading it waits for
// nothing but a lock held for the copy itself — so whatever CoreAudio is doing, the tick returns.

import os

/// The transport facts the tick needs, as the engine last sampled them.
public struct TransportSnapshot: Sendable, Equatable {
    /// The playhead within the current track, in seconds; `nil` while nothing reports one (stopped,
    /// starting, or the output just went away).
    public var position: Double?
    /// Completed gapless seams on the active path: an increase means the on-deck track is current.
    public var transitionCount: UInt64
    /// The current track ended with nothing on deck.
    public var ended: Bool

    public init(position: Double? = nil, transitionCount: UInt64 = 0, ended: Bool = false) {
        self.position = position
        self.transitionCount = transitionCount
        self.ended = ended
    }
}

/// The latest value one domain published, for another to read without waiting on the publisher's
/// work. The publisher does its work (the reads that can block) first and hands over a finished
/// value; the lock covers only the copy in or out. There is no way to run caller code under it, so
/// a publisher stuck in its work leaves readers the previous value, never a wait.
public final class SnapshotChannel<Value: Sendable>: Sendable {
    private let latest: OSAllocatedUnfairLock<Value>

    public init(_ initial: Value) {
        latest = OSAllocatedUnfairLock(initialState: initial)
    }

    /// The last published value.
    public func read() -> Value {
        latest.withLock { $0 }
    }

    /// Replace the value readers see.
    public func publish(_ value: Value) {
        latest.withLock { $0 = value }
    }
}
