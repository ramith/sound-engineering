import Foundation

// MARK: - Search filter decisions (S9.5 — pure filter logic)

/// Monotonic newest-wins guard for the async Songs-filter read. Extracted from `LibraryBrowseModel`
/// so the H2 "no stale phantom publish" contract is unit-testable. Usage: the model calls
/// `invalidate()` **synchronously on every `searchQuery` edit** (before the ~120 ms debounce), and each
/// read takes its token from `beginRead()` and publishes its result only if `isCurrent(token)` still
/// holds — so an in-flight read for an older query can never overwrite a newer edit (review LOW-1), and
/// of two reads of the SAME query the newer always wins (council C-58 / P5B-01: a filtered reload re-runs
/// the read with no edit, once per library change, and the store reads concurrently, so two reads can
/// finish in either order — the older snapshot, without the newly scanned song, must not land last).
public struct SearchEpoch: Sendable, Equatable {
    private var value = 0

    public init() {}

    /// Invalidate every read begun so far. Call synchronously on every edit — NOT inside the debounce,
    /// or a fast read can resolve and publish before the invalidation lands.
    public mutating func invalidate() {
        value &+= 1
    }

    /// Begin a read: it supersedes every read begun before it. Returns its token for `isCurrent`.
    public mutating func beginRead() -> Int {
        invalidate()
        return value
    }

    /// Whether the read holding `token` may still publish: no edit and no newer read since it began.
    public func isCurrent(_ token: Int) -> Bool {
        token == value
    }
}

/// The incremental-filter gate: run the FTS read only at ≥ `minimumLength` trimmed characters.
/// Below it, the model restores the full list (nil `matchedIDs`). Length-only — tokenizable-but-junk
/// input (e.g. `"!!!"`) passes the gate and the DAO correctly returns zero matches.
public enum SearchQueryGate {
    public static let minimumLength = 2

    public static func shouldQuery(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumLength
    }
}
