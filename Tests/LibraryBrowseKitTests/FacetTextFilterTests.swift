import LibraryBrowseKit
import Testing

// MARK: - FacetTextFilter (S9.6 — per-section in-place filter; R1.1-B — the one word-start rule)

@Suite("FacetTextFilter — the one search rule: every query word starts a word")
struct FacetTextFilterTests {
    @Test("empty / whitespace query matches everything (filter off)")
    func emptyMatchesAll() {
        #expect(FacetTextFilter.matches("The Beatles", query: ""))
        #expect(FacetTextFilter.matches("The Beatles", query: "   "))
        #expect(FacetTextFilter.matches(["Abbey Road", "The Beatles"], query: "\n"))
    }

    @Test("case-insensitive word start on the single candidate")
    func singleWordStart() {
        #expect(FacetTextFilter.matches("The Beatles", query: "beat"))
        #expect(FacetTextFilter.matches("Jazz", query: "JAZ"))
        #expect(!FacetTextFilter.matches("The Beatles", query: "zeppelin"))
    }

    /// The founder's decision (2026-10-25): the grids matched substrings until R1.1-B; now a word must start
    /// with what is typed — "eyon" no longer finds "Beyoncé" (accepted).
    @Test("the middle of a word no longer matches (“eyon” ≠ “Beyoncé”, “eatles” ≠ “The Beatles”)")
    func noSubstring() {
        #expect(!FacetTextFilter.matches("Beyoncé", query: "eyon"))
        #expect(!FacetTextFilter.matches("The Beatles", query: "eatles"))
        #expect(FacetTextFilter.matches("Beyoncé", query: "beyo"))
    }

    @Test("a filter of only punctuation is active and keeps nothing, as the Songs search finds nothing")
    func punctuationOnly() {
        #expect(FacetTextFilter.isActive("!!!"))
        #expect(!FacetTextFilter.matches("Anything", query: "!!!"))
    }

    @Test("filter keeps the matches in the list's own order, the query read once")
    func filterKeepsOrder() {
        let names = ["Rock and Roll", "Jazz", "Punk Rock", "Rockabilly"]
        #expect(FacetTextFilter.filter(names, query: "rock") { [$0] } == ["Rock and Roll", "Punk Rock", "Rockabilly"])
        #expect(FacetTextFilter.filter(names, query: " ") { [$0] } == names)
    }

    @Test("matches when ANY candidate contains the query (e.g. album title OR artist)")
    func anyCandidate() {
        #expect(FacetTextFilter.matches(["Abbey Road", "The Beatles"], query: "beatles")) // 2nd matches
        #expect(FacetTextFilter.matches(["Abbey Road", "The Beatles"], query: "road")) // 1st matches
        #expect(!FacetTextFilter.matches(["Abbey Road", "The Beatles"], query: "queen"))
    }

    @Test("the query is trimmed before matching")
    func trimmed() {
        #expect(FacetTextFilter.matches("Jazz", query: "  jazz  "))
    }

    @Test("a filter is active only when it narrows: text beyond whitespace")
    func isActive() {
        #expect(!FacetTextFilter.isActive(""))
        #expect(!FacetTextFilter.isActive("  \n"))
        #expect(FacetTextFilter.isActive("ja"))
        #expect(FacetTextFilter.isActive(" j "))
    }

    @Test("diacritic-insensitive (S10.7 §5 queue-filter contract)")
    func diacriticInsensitive() {
        #expect(FacetTextFilter.matches("Beyoncé", query: "beyonce"))
        #expect(FacetTextFilter.matches("Sigur Rós", query: "ros"))
        #expect(FacetTextFilter.matches("Motörhead", query: "motorhead"))
    }
}
