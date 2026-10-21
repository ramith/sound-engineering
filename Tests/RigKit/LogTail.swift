// The product's `[UX]` log, kept quietly in memory while tests run, and shown when one fails.
//
// Parallel tests wrote some 200,000 `[UX]` lines (33 MB) to stderr per CI run: synchronous writes that
// add timing noise and bury the one failure line (hazard P3). A test target points the product's log
// sink here; a suite that wants the tail on failure carries `.attachingLogTail`.

import Synchronization
public import Testing

/// A bounded ring of the most recent log lines, shared by every test in the process.
public final class LogTail: Sendable {
    /// The one in the process.
    public static let shared = LogTail()

    private static let capacity = 2000
    private let lines = Mutex<[String]>([])

    /// Keep `line`, dropping the oldest past the capacity.
    public func append(_ line: String) {
        lines.withLock {
            $0.append(line)
            if $0.count > Self.capacity {
                $0.removeFirst($0.count - Self.capacity)
            }
        }
    }

    /// The last `count` lines, oldest first, one per line.
    public func tail(_ count: Int = 200) -> String {
        lines.withLock { $0.suffix(count).joined(separator: "\n") }
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
