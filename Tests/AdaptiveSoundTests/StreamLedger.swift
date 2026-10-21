@testable import AdaptiveSound
import Foundation
import Synchronization

/// The Enhanced rig's account of the completion chain (R4): every buffer, segment or file the bridge
/// scheduled on the player, in the order the player consumes them, and which completions have been handed
/// on. AVFAudio reports a buffer consumed some 150 µs AFTER the render that consumed it, on a thread of
/// its own — and exactly when the frames rendered since the schedule began reach the buffer's end (probed:
/// `dataConsumed` and `dataRendered` alike). So after rendering `rendered` frames the completions DUE are
/// those whose buffer ends by then, and a render that waits until none is undelivered keeps the chain in
/// step with the player — as a device's pace merely hoped it would.
final class StreamLedger: StreamObserver {
    private struct Entry {
        let token: Int
        /// Where the buffer ends, in frames from the start of the schedule.
        let end: Int64
    }

    private struct State {
        var epoch = 0
        var nextToken = 0
        var scheduledFrames: Int64 = 0
        var owed: [Entry] = []
        /// Superseded before they were heard: `stop()` fires their completions all the same.
        var orphans: Set<Int> = []
    }

    private let state = Mutex(State())

    func scheduled(frames: Int64) -> Int {
        state.withLock {
            $0.nextToken += 1
            $0.scheduledFrames += frames
            $0.owed.append(Entry(token: $0.nextToken, end: $0.scheduledFrames))
            return $0.nextToken
        }
    }

    func delivered(_ token: Int) {
        state.withLock {
            $0.owed.removeAll { $0.token == token }
            $0.orphans.remove(token)
        }
    }

    func superseded() {
        state.withLock {
            $0.epoch += 1
            $0.scheduledFrames = 0
            $0.orphans.formUnion($0.owed.map(\.token))
            $0.owed.removeAll()
        }
    }

    /// Which schedule is current: it changes when a stop or a seek supersedes the last.
    var epoch: Int {
        state.withLock { $0.epoch }
    }

    /// How many completions are due once `rendered` frames of the current schedule have been rendered,
    /// and not yet handed on.
    func undelivered(dueBy rendered: Int64) -> Int {
        state.withLock { $0.owed.count { $0.end <= rendered } }
    }

    /// How many completions a stop or seek set off and that have not been handed on yet.
    var undeliveredFromSuperseded: Int {
        state.withLock { $0.orphans.count }
    }
}
