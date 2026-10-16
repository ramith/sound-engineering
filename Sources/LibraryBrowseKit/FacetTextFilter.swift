import Foundation

// MARK: - FacetTextFilter (S9.6 — in-place, in-memory list filter)

/// The pure decision behind the per-section Filter field: does a facet row match the filter text?
/// A substring match read by the Library's word rule (`SearchFold`: case, width and a Latin letter's
/// accents ignored — "beyonce" matches "Beyoncé", the S10.7 §5 queue-filter contract — while any other
/// script's marks count, so "මාල" never matches "මිල", as in the Songs search; council C-61 / P5A-04)
/// over one or more candidate strings (e.g. an album matches on its title OR its artist). An
/// empty/whitespace query matches everything (filter off). This mirrors Apple Music's Filter
/// field — a lexical match that narrows the current list in place — NOT the FTS catalog search
/// the Songs tab uses (one match shape for both is R1.1-B's one search rule).
public enum FacetTextFilter {
    public static func matches(_ candidates: [String], query: String) -> Bool {
        let trimmed = normalized(query)
        guard !trimmed.isEmpty else { return true }
        return candidates.contains { SearchFold.text($0, contains: trimmed) }
    }

    /// Convenience for a single candidate (Artists / Genres filter on their name).
    public static func matches(_ candidate: String, query: String) -> Bool {
        matches([candidate], query: query)
    }

    /// Whether `query` narrows anything: false for an empty or whitespace-only filter, which
    /// matches everything — so a card header's count line reads "N albums", not "N results".
    public static func isActive(_ query: String) -> Bool {
        !normalized(query).isEmpty
    }

    private static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
