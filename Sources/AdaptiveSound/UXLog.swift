import Foundation
import Synchronization

// MARK: - UX Logging helpers

/// Where `[UX]` lines go. The product's sink is `NSLog`, unconditional (the codebase convention) and
/// trivially cheap — not a logging framework. A test target swaps it for an in-memory ring
/// (`UXLog.sink.withLock { $0 = … }`): parallel tests wrote some 200,000 `[UX]` lines per CI run, and
/// synchronous stderr writes both add timing noise and bury the one failure line.
enum UXLog {
    /// What receives a line: the message only (the sink adds the `[UX]` tag).
    ///
    /// A struct holding the closure, NOT a bare closure in the `Mutex`: a function stored in generic
    /// storage is reabstracted on every `inout` access, and the write-back wraps it in two more thunks —
    /// a closure that grows by two frames per log line, until the stack overflows (the OnDeck explorer's
    /// 100,000 lines found it). A struct's field is not reabstracted.
    struct Sink: Sendable {
        let write: @Sendable (String) -> Void
    }

    /// The process-wide sink; `NSLog` until a test replaces it.
    static let sink = Mutex(Sink { message in NSLog("[UX] \(message)") })
}

/// Emit a `[UX]` tagged line to the process's sink (`UXLog.sink`): `NSLog` in the app.
func logUX(_ message: String) {
    let sink = UXLog.sink.withLock { $0 }
    sink.write(message)
}

/// Format a duration / position value as `"%.2f"` seconds.
/// Used by `[UX]` log lines to keep seconds formatting consistent across call sites.
func secs(_ value: Double) -> String {
    String(format: "%.2f", value)
}
