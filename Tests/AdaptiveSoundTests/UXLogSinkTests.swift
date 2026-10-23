// UXLOG — the product's `[UX]` log goes through one swappable sink (test-rig redesign, hazard P3), and a
// line costs the same however many came before it.

@testable import AdaptiveSound
import Foundation
import RigKit
import Synchronization
import Testing

@Suite("The [UX] log sink", .timeLimit(.minutes(3)))
struct UXLogSinkTests {
    @Test("UXLOG-01: 200,000 lines through the installed sink grow nothing — the stack stays flat")
    func linesReachTheSinkWithoutGrowth() {
        // A closure kept in a generic Mutex is reabstracted on every access and wraps itself in two more
        // thunks per line: this many lines overflowed the stack (OnDeckExplorer, SIGBUS) before the sink
        // became a struct. The process-wide sink is NOT swapped (other tests log into it meanwhile, and
        // their failure tails would go missing): the quiet sink is the one under test, and the ring counts
        // what reached it.
        QuietLog.install()
        let before = LogTail.shared.totalAppended
        for index in 0 ..< 200_000 {
            logUX("uxlog-01 line \(index)")
        }
        let arrived = LogTail.shared.totalAppended - before
        // Other tests log into the same ring meanwhile, so at least ours arrived.
        #expect(arrived >= 200_000, "only \(arrived) of 200000 lines reached the sink")
    }

    @Test("UXLOG-02: a sink read through a Mutex 100,000 times is called each time, unwrapped")
    func sinkReadThroughAMutexIsCalledEachTime() {
        // The shape the app relies on: a value read out of a Mutex and called, with no re-wrapping.
        let sentinel = Atomic<Int>(0)
        let probe = Mutex(UXLog.Sink { _ in sentinel.add(1, ordering: .relaxed) })
        for _ in 0 ..< 100_000 {
            let sink = probe.withLock { $0 }
            sink.write("x")
        }
        let calls = sentinel.load(ordering: .relaxed)
        #expect(calls == 100_000, "a sink read through a Mutex was called \(calls) times, not 100000")
    }
}
