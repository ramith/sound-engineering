// Deadline — a bounded-wait helper for the concurrency case (design §6-D).
//
// The concurrency stress/snapshot phases MUST be bounded: a phase that never finishes is a
// DEADLOCK and must FAIL — loudly, naming the check — never hang. The deadline is a WATCHDOG
// THREAD, not a task in the operation's own task group: a group waits for all its children, even
// cancelled ones, so a deadline raced inside one cannot fire while a child is wedged in a
// non-cooperative wait (`DispatchSemaphore.wait()`, a synchronous SQLite call). The watchdog sleeps
// on its own thread, outside the cooperative pool, and when the time is up it prints which check
// and which phase did not finish and exits non-zero. The cap only ever breaks a hang: every phase
// finishes in well under a second when nothing is wrong.

import Foundation
import Synchronization

/// The check the driver is running now, for the watchdog's message.
enum CurrentCheck {
    private static let running = Mutex("no check running")

    static func begin(number: Int, label: String) {
        running.withLock { $0 = "check \(number) (\(label))" }
    }

    static var name: String {
        running.withLock { $0 }
    }
}

/// Run `operation` and return its value. If it has not finished within `seconds`, the watchdog
/// prints `what` and the running check's name and exits 1 — whatever the operation is blocked on.
/// Rethrows anything `operation` throws.
func withDeadline<T: Sendable>(
    _ what: String, seconds: Double, operation: @Sendable () async throws -> T
) async rethrows -> T {
    let finished = DispatchSemaphore(value: 0)
    let check = CurrentCheck.name
    Thread.detachNewThread {
        guard finished.wait(timeout: .now() + seconds) == .timedOut else { return }
        fail("\(check): \(what) did NOT finish within \(Int(seconds)) s — a deadlock "
            + "(the watchdog thread fired; the operation never returned)")
    }
    defer { finished.signal() }
    return try await operation()
}

/// Wait on a parked rendezvous — `gate` is signalled by the state named `what` — or fail naming the
/// running check and that state. For the non-cooperative parks inside a sync closure: they are
/// released by the test, never by time; the cap only breaks a hang.
func awaitState(_ gate: DispatchSemaphore, _ what: String, seconds: Double = 60) {
    guard gate.wait(timeout: .now() + seconds) == .timedOut else { return }
    fail("\(CurrentCheck.name): \(what) did NOT happen within \(Int(seconds)) s — the park was never released")
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
        if first {
            body()
        }
    }
}
