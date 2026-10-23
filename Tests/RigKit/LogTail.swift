// The product's `[UX]` log, kept quietly in memory while tests run, and shown when one fails.
//
// Parallel tests wrote some 200,000 `[UX]` lines (33 MB) to stderr per CI run: synchronous writes that
// add timing noise and bury the one failure line (hazard P3). A test target points the product's log
// sink here; a suite that wants the tail on failure carries `.attachingLogTail`.

import Synchronization
import Testing

/// A bounded ring of the most recent log lines, shared by every test in the process.
public final class LogTail: Sendable {
    /// The one in the process.
    public static let shared = LogTail()

    private static let capacity = 2000

    /// A fixed ring: `next` is where the next line goes, `total` how many were ever appended.
    private struct Ring {
        var slots = [String](repeating: "", count: LogTail.capacity)
        var next = 0
        var total = 0
    }

    private let ring = Mutex(Ring())

    /// Keep `line`, overwriting the oldest once the ring is full: O(1), however many lines came before.
    public func append(_ line: String) {
        ring.withLock {
            $0.slots[$0.next] = line
            $0.next = ($0.next + 1) % Self.capacity
            $0.total += 1
        }
    }

    /// How many lines were ever appended, kept or not.
    public var totalAppended: Int {
        ring.withLock { $0.total }
    }

    /// The last `count` lines, oldest first, one per line.
    public func tail(_ count: Int = 200) -> String {
        ring.withLock { state in
            let kept = min(count, state.total, Self.capacity)
            let start = (state.next - kept + Self.capacity) % Self.capacity
            return (0 ..< kept).map { state.slots[(start + $0) % Self.capacity] }.joined(separator: "\n")
        }
    }
}

public extension Trait where Self == IssueHandlingTrait {
    /// Attach the tail of the product's `[UX]` log (`LogTail.shared`) to every issue a test of this suite
    /// records, so a failure shows what the app was doing. Other tests of the process log into the same
    /// ring, so the tail may hold their lines too.
    static var attachingLogTail: Self {
        .compactMapIssues { issue in
            Attachment.record(LogTail.shared.tail(), named: "UX log tail")
            return issue
        }
    }
}
