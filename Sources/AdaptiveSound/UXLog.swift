import Foundation

// MARK: - UX Logging helpers

/// Emit a `[UX]` tagged line via NSLog. Unconditional (matches the existing codebase
/// convention) and trivially cheap — a direct NSLog wrapper, not a logging framework.
func logUX(_ message: String) {
    NSLog("[UX] \(message)")
}

/// Format a duration / position value as `"%.2f"` seconds.
/// Used by `[UX]` log lines to keep seconds formatting consistent across call sites.
func secs(_ value: Double) -> String {
    String(format: "%.2f", value)
}
