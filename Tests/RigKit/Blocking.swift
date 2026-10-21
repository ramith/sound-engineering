// Blocking test code, kept OFF the shared cooperative pool (hazard P2).
//
// swift-testing runs tests as tasks on the Swift cooperative pool, which has one thread per core: three
// on a CI runner. A test that blocks one — `Thread.sleep`, a semaphore, `queue.sync`, a long synchronous
// render — takes a third of the pool from every other test, and a handful of them starves it (PR #91:
// six-second fixtures took nineteen). `blocking` runs such work on a thread of its own and awaits it.

import Foundation

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
