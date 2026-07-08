import Foundation

// MARK: - Search filter decisions (S9.5 — pure filter logic)

/// Monotonic newest-wins guard for the async Songs-filter read. Extracted from `LibraryBrowseModel`
/// so the H2 "no stale phantom publish" contract is unit-testable. Usage: the model calls
/// `invalidate()` **synchronously on every `searchQuery` edit** (before the ~120 ms debounce), then a
/// debounced read `captures` `value` and publishes its result only if `isCurrent(captured)` still
/// holds — so an in-flight read for an older query can never overwrite a newer edit (review LOW-1).
public struct SearchEpoch: Sendable, Equatable {
    public private(set) var value: Int

    public init(value: Int = 0) {
        self.value = value
    }

    /// Invalidate any in-flight read. Call synchronously on every edit — NOT inside the debounce,
    /// or a fast read can resolve and publish before the invalidation lands.
    public mutating func invalidate() {
        value &+= 1
    }

    /// Whether a read that captured `captured` may still publish (no newer edit has landed since).
    public func isCurrent(_ captured: Int) -> Bool {
        captured == value
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
