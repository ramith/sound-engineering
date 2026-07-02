// Deadline — a bounded-wait helper for the concurrency case (design §6-D).
//
// The concurrency stress/snapshot phases MUST be bounded: a phase that never
// finishes is a DEADLOCK and must be a FAIL, never a hang or a skip. `withDeadline`
// races the async `operation` against a wall-clock timeout using a task group; the
// first to finish wins and the loser is cancelled. A `nil` result means the timeout
// won (⇒ the caller fails the check).

import Foundation

/// Run `operation`, returning its value, or `nil` if `seconds` elapse first (the
/// operation is then cancelled). Rethrows anything `operation` throws.
///
/// Note: SQLite calls are synchronous C and do not observe Swift cancellation, so a
/// truly wedged SQLite call could still outlive the timeout at the C level; in
/// practice the store's `busy_timeout` bounds every lock wait, so a timeout here
/// reflects a genuine logic deadlock in the test's task graph — exactly what §6-D
/// wants surfaced as a FAIL.
func withDeadline<T: Sendable>(
    seconds: Double, operation: @escaping @Sendable () async throws -> T
) async throws -> T? {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        // The first task to finish decides the result; cancel the rest.
        let first = try await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

/// A thread-safe one-shot: `runOnce`'s body executes on the FIRST call only. Used to gate
/// a scan's synchronous `progress` closure so a mid-scan rendezvous parks EXACTLY once
/// (after the first committed batch), never on later batches. `@unchecked Sendable` is
/// sound: the single `Bool` is guarded by the lock. (A `DispatchSemaphore(value: 1)` used
/// as a latch would deadlock-safe but trap at deallocation once decremented and never
/// restored — `value < initial` — so a lock is the correct primitive here.)
final class OneShotLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var hasRun = false

    func runOnce(_ body: () -> Void) {
        lock.lock()
        let first = !hasRun
        hasRun = true
        lock.unlock()
        if first { body() }
    }
}
