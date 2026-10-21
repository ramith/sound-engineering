// UXLOG — the product's `[UX]` log goes through one swappable sink (test-rig redesign, hazard P3), and a
// line costs the same however many came before it.

@testable import AdaptiveSound
import Foundation
import Synchronization
import Testing

@Suite("The [UX] log sink", .timeLimit(.minutes(3)))
struct UXLogSinkTests {
    @Test("UXLOG-01: a line reaches the installed sink, and 200,000 lines grow nothing — the stack stays flat")
    func linesReachTheSinkWithoutGrowth() {
        // A closure kept in a generic Mutex is reabstracted on every access and wraps itself in two more
        // thunks per line: this many lines overflowed the stack (OnDeckExplorer, SIGBUS) before the sink
        // became a struct.
        QuietLog.install() // so what is swapped back is the quiet sink, whichever test installs it first
        let seen = Atomic<Int>(0)
        let previous = UXLog.sink.withLock { sink in
            defer { sink = UXLog.Sink { _ in seen.add(1, ordering: .relaxed) } }
            return sink
        }
        for index in 0 ..< 200_000 {
            logUX("line \(index)")
        }
        UXLog.sink.withLock { $0 = previous }
        let count = seen.load(ordering: .relaxed)
        // Other tests log into the same sink while it is swapped, so at least ours arrived.
        #expect(count >= 200_000, "only \(count) of 200000 lines reached the sink")
    }
}
