import Foundation

// MARK: - FacetTextFilter (S9.6 — in-place, in-memory list filter)

/// The pure decision behind the per-section Filter field: does a facet row match the filter text?
/// A case- AND diacritic-insensitive substring match ("beyonce" matches "Beyoncé" — the S10.7 §5
/// queue-filter contract, via `localizedStandardContains`, Apple's user-facing-search comparison)
/// over one or more candidate strings (e.g. an album matches on its title OR its artist). An
/// empty/whitespace query matches everything (filter off). This mirrors Apple Music's Filter
/// field — a lexical match that narrows the current list in place — NOT the FTS catalog search
/// the Songs tab uses.
public enum FacetTextFilter {
    public static func matches(_ candidates: [String], query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return candidates.contains { $0.localizedStandardContains(trimmed) }
    }

    /// Convenience for a single candidate (Artists / Genres filter on their name).
    public static func matches(_ candidate: String, query: String) -> Bool {
        matches([candidate], query: query)
    }
}
