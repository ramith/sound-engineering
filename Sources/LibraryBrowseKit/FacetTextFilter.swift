import Foundation
import LibraryStore

// MARK: - FacetTextFilter (S9.6 — in-place, in-memory list filter; R1.1-B — the one search rule)

/// The pure decision behind the per-section Filter field: does a list row match the filter text? The
/// Library's one search rule (`SearchRule`, R1.1-B, US-R1F-14; founder 2026-10-25): every word of the
/// filter must START a word of one of the row's candidate strings, in any order — an album matches on its
/// title OR its artist ("beyo" finds Beyoncé's albums; "eyon" no longer does — accepted). Case, width and
/// a Latin letter's accents don't count ("beyonce" matches "Beyoncé", the S10.7 §5 queue-filter
/// contract); every other script's marks do ("මාල" never matches "මිල"; council C-61 / P5A-04) — the same
/// words the Songs search index reads, so one filter finds the same items in every tab. Each tab keeps its
/// own sort: the filter only narrows. An empty or whitespace-only filter matches everything (filter off);
/// one with no word in it (only punctuation) matches nothing, as Songs finds nothing for it.
public enum FacetTextFilter {
    public static func matches(_ candidates: [String], query: String) -> Bool {
        guard isActive(query) else { return true }
        return SearchRule.Query(query).matches(candidates)
    }

    /// Convenience for a single candidate (Artists / Genres filter on their name).
    public static func matches(_ candidate: String, query: String) -> Bool {
        matches([candidate], query: query)
    }

    /// The items of `items` that `query` keeps, in their own order — the query read once for the whole
    /// list. Every item when the filter is off.
    public static func filter<Items: Sequence>(
        _ items: Items, query: String, candidates: (Items.Element) -> [String]
    ) -> [Items.Element] {
        guard isActive(query) else { return Array(items) }
        let compiled = SearchRule.Query(query)
        return items.filter { compiled.matches(candidates($0)) }
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
