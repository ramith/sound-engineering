import LibraryBrowseKit
import Testing

// MARK: - FacetTextFilter (S9.6 — per-section in-place filter)

@Suite("FacetTextFilter — case-insensitive substring narrow")
struct FacetTextFilterTests {
    @Test("empty / whitespace query matches everything (filter off)")
    func emptyMatchesAll() {
        #expect(FacetTextFilter.matches("The Beatles", query: ""))
        #expect(FacetTextFilter.matches("The Beatles", query: "   "))
        #expect(FacetTextFilter.matches(["Abbey Road", "The Beatles"], query: "\n"))
    }

    @Test("case-insensitive substring on the single candidate")
    func singleSubstring() {
        #expect(FacetTextFilter.matches("The Beatles", query: "beat"))
        #expect(FacetTextFilter.matches("Jazz", query: "JAZ"))
        #expect(!FacetTextFilter.matches("The Beatles", query: "zeppelin"))
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
}
