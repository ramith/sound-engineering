// Blocking test code, kept OFF the shared cooperative pool (hazard P2).
//
// swift-testing runs tests as tasks on the Swift cooperative pool, which has one thread per core: three
// on a CI runner. A test that blocks one — `Thread.sleep`, a semaphore, `queue.sync`, a long synchronous
// render — takes a third of the pool from every other test, and a handful of them starves it (PR #91:
// six-second fixtures took nineteen). `blocking` runs such work on a thread of its own and awaits it.

import Foundation
import Testing

/// Run `work` on a dedicated thread, named `name`, and return what it returns (or throw what it throws).
/// The caller suspends meanwhile; no pool thread is held. `work` cannot be cancelled once started, so it
/// must be bounded by what it waits for (`until` inside it is not available: it is synchronous).
public func blocking<Value: Sendable>(
    _ name: String,
    _ work: @escaping @Sendable () throws -> Value
) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
        let thread = Thread {
            continuation.resume(with: Result { try work() })
        }
        thread.name = "rig.blocking.\(name)"
        thread.qualityOfService = .userInitiated
        thread.start()
    }
}

/// Wait, ON A THREAD OF ITS OWN (inside `blocking`), until `condition` holds: the synchronous twin of
/// `until`, for blocking test code that cannot suspend. It never runs on the cooperative pool. At its cap it
/// THROWS `RigTimeout`, naming the state, exactly as `until` does.
public func untilBlocking(
    _ what: String,
    cap: Duration = .seconds(120),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () throws -> Bool
) throws {
    let deadline = SuspendingClock.now + cap
    var naps = 0
    while try !condition() {
        guard SuspendingClock.now < deadline else {
            throw RigTimeout(what: what, cap: cap, location: sourceLocation)
        }
        // Stay hot for a moment (a completion is ~150 µs away), then nap longer.
        naps += 1
        usleep(naps < 200 ? 50 : 1000)
    }
}

/// A thread of its own to run a whole ASYNC task on (`Task(executorPreference: executor) { … }`), for code
/// under test that blocks inside an async function it runs — a scanner's progress callback held by a test —
/// where `blocking {}` (sync work only) does not fit. The task's non-isolated async code, and its resumptions
/// after each `await`, run on this executor's queue instead of the cooperative pool.
public final class OffPoolExecutor: TaskExecutor, @unchecked Sendable {
    private let queue: DispatchQueue

    /// - Parameter name: the queue's (and thread's) label.
    public init(_ name: String) {
        queue = DispatchQueue(label: "rig.offpool.\(name)", qos: .userInitiated)
    }

    public func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        queue.async {
            unowned.runSynchronously(on: self.asUnownedTaskExecutor())
        }
    }
}
