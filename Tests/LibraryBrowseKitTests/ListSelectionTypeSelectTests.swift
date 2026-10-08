import LibraryBrowseKit
import Testing

// MARK: - ListSelection type-to-select (SEL-06) and the no-columns contract (COL-01)

/// A list row as the kit sees one: an id and the title the list shows. Nothing else — no columns,
/// no sort keys — which is all an album, artist or genre page can hand it too (COL-01).
private struct Row: Identifiable {
    let id: Int
    let title: String
}

@Suite("ListSelection — type-to-select (SEL-06), and no column or sort dependency (COL-01)")
struct ListSelectionTypeSelectTests {
    private typealias Selection = ListSelection<Int>
    /// Display order — deliberately NOT alphabetical, as when Songs is sorted by artist.
    private let rows = [
        Row(id: 1, title: "Windowlicker"),
        Row(id: 2, title: "Bohemian Rhapsody"),
        Row(id: 3, title: "Beyoncé — Halo"),
        Row(id: 4, title: "Blackbird"),
        Row(id: 5, title: "Bach: Cello Suite No. 1"),
    ]
    private let start = ContinuousClock.now

    private func at(milliseconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .milliseconds(milliseconds))
    }

    // MARK: SEL-06

    @Test("SEL-06 a letter selects the FIRST row in display order whose title starts with it")
    func firstMatchInDisplayOrder() {
        var selection = Selection()
        #expect(selection.typeSelect("b", at: at(milliseconds: 0), in: rows, title: \.title) == 2)
        #expect(selection.ids == [2])
        #expect(selection.anchor == 2)
        #expect(selection.cursor == 2)
    }

    @Test("SEL-06 keys typed quickly extend the search")
    func typingExtends() {
        var selection = Selection()
        selection.typeSelect("b", at: at(milliseconds: 0), in: rows, title: \.title)
        #expect(selection.typeSelect("l", at: at(milliseconds: 300), in: rows, title: \.title) == 4)
        #expect(selection.typeSelect("a", at: at(milliseconds: 600), in: rows, title: \.title) == 4)
    }

    @Test("SEL-06 a pause longer than the reset interval starts a new search")
    func pauseStartsOver() {
        var selection = Selection()
        selection.typeSelect("b", at: at(milliseconds: 0), in: rows, title: \.title)
        #expect(selection.typeSelect("w", at: at(milliseconds: 1500), in: rows, title: \.title) == 1)
    }

    @Test("SEL-06 the reset interval is measured from the LAST key, not the first")
    func intervalFromLastKey() {
        var selection = Selection()
        selection.typeSelect("b", at: at(milliseconds: 0), in: rows, title: \.title)
        selection.typeSelect("a", at: at(milliseconds: 800), in: rows, title: \.title)
        #expect(selection.typeSelect("c", at: at(milliseconds: 1600), in: rows, title: \.title) == 5)
    }

    @Test("SEL-06 the match ignores case and diacritics")
    func caseAndDiacritics() {
        var selection = Selection()
        #expect(selection.typeSelect("BEYO", at: at(milliseconds: 0), in: rows, title: \.title) == 3)
        var plain = Selection()
        #expect(plain.typeSelect("beyonce", at: at(milliseconds: 0), in: rows, title: \.title) == 3)
    }

    @Test("SEL-06 a prefix only: a title CONTAINING the search does not match")
    func prefixOnly() {
        var selection = Selection()
        #expect(selection.typeSelect("halo", at: at(milliseconds: 0), in: rows, title: \.title) == nil)
    }

    @Test("SEL-06 no match leaves the selection as it was")
    func noMatchKeepsSelection() {
        var selection = Selection()
        selection.click(4, extend: false, toggle: false, in: rows.map(\.id))
        #expect(selection.typeSelect("z", at: at(milliseconds: 0), in: rows, title: \.title) == nil)
        #expect(selection.ids == [4])
        #expect(selection.cursor == 4)
    }

    @Test("SEL-06 an arrow (or any other selection verb) ends the search")
    func otherVerbEndsSearch() {
        var selection = Selection()
        selection.typeSelect("b", at: at(milliseconds: 0), in: rows, title: \.title)
        selection.move(.step(1), extend: false, in: rows.map(\.id))
        // Within the interval, but the arrow ended the search: "w" is a new search, not "bw".
        #expect(selection.typeSelect("w", at: at(milliseconds: 200), in: rows, title: \.title) == 1)
    }

    @Test("SEL-06 only the rows handed in are searched — a filter-hidden title never matches")
    func searchesCurrentRowsOnly() {
        var selection = Selection()
        let filtered = rows.filter { $0.id != 2 }
        #expect(selection.typeSelect("b", at: at(milliseconds: 0), in: filtered, title: \.title) == 3)
    }

    // MARK: COL-01

    @Test("COL-01 the kit runs a column-less, sort-less list — an album page's tracks in disc order")
    func albumPageWithoutColumns() {
        // Ids are plain Ints, rows carry only a title, and the order is whatever the page shows:
        // nothing about Songs' column settings or its sort is needed or consulted.
        let albumTracks = [Row(id: 7, title: "Come Together"), Row(id: 8, title: "Something"),
                           Row(id: 9, title: "Maxwell's Silver Hammer")]
        let ids = albumTracks.map(\.id)
        var selection = Selection()
        selection.click(7, extend: false, toggle: false, in: ids)
        selection.move(.last, extend: true, in: ids)
        #expect(selection.ids == [7, 8, 9])
        #expect(selection.typeSelect("s", at: at(milliseconds: 0), in: albumTracks, title: \.title) == 8)
        selection.selectAll(in: ids)
        #expect(selection.ids == [7, 8, 9])
    }
}
