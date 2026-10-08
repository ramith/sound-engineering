import LibraryBrowseKit
import Testing

// MARK: - Facet browse decisions (S9.6 — pure count/detail-state/visibility)

@Suite("FacetDecisions — count label, detail state, list visibility")
struct FacetDecisionsTests {
    @Test("FacetCountLabel singularizes at 1 and groups large counts")
    func countLabel() {
        #expect(FacetCountLabel.songs(count: 0) == "0 songs")
        #expect(FacetCountLabel.songs(count: 1) == "1 song")
        #expect(FacetCountLabel.songs(count: 2) == "2 songs")
        // Grouping is locale-formatted (matches the Songs-tab count line), so assert against
        // the same formatter rather than a hardcoded "1,234".
        #expect(FacetCountLabel.songs(count: 1234) == "\(1234.formatted(.number)) songs")
    }

    @Test("a card header's count line: the noun pluralized, or \"N results\" while filtered (D4)")
    func cardCountLine() {
        #expect(FacetCountLabel.count(857, noun: "album", filtered: false) == "857 albums")
        #expect(FacetCountLabel.count(1, noun: "genre", filtered: false) == "1 genre")
        #expect(FacetCountLabel.count(0, noun: "artist", filtered: false) == "0 artists")
        #expect(FacetCountLabel.count(12, noun: "album", filtered: true) == "12 results")
        #expect(FacetCountLabel.count(1, noun: "album", filtered: true) == "1 result")
        #expect(FacetCountLabel.count(0, noun: "song", filtered: true) == "0 results")
        #expect(FacetCountLabel.count(1234, noun: "song", filtered: false) == "\(1234.formatted(.number)) songs")
    }

    @Test("FacetDetailState: 0 -> empty, >0 -> list")
    func detailState() {
        #expect(FacetDetailState.state(trackCount: 0) == .empty)
        #expect(FacetDetailState.state(trackCount: 1) == .list)
        #expect(FacetDetailState.state(trackCount: 500) == .list)
    }

    @Test("FacetListVisibility hides 0-song facets")
    func visibility() {
        #expect(FacetListVisibility.isVisible(trackCount: 0) == false)
        #expect(FacetListVisibility.isVisible(trackCount: 1) == true)
    }
}
