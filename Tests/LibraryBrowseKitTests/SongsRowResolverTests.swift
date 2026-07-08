import LibraryBrowseKit
import Testing

// MARK: - SongsRowResolver (S9.5 — visible-subset play/context resolution, review #3)

/// A trivial `Identifiable` stub — the resolver is generic, so tests need no `LibraryTrackDisplay`
/// fixtures. `id` stands in for a track id; distinct ids model duplicate-titled tracks.
private struct Row: Identifiable, Equatable { let id: Int64 }

@Suite("SongsRowResolver — resolve over the visible subset, by id")
struct SongsRowResolverTests {
    private let visible = [Row(id: 10), Row(id: 20), Row(id: 30), Row(id: 40)]

    @Test("primaryRow = the FIRST visible row (sort order) whose id is selected")
    func primaryFirstInOrder() {
        // selection order is irrelevant; visible order wins → 20 before 30.
        #expect(SongsRowResolver.primaryRow(in: visible, selection: [30, 20]) == Row(id: 20))
    }

    @Test("primaryRow is nil when the selection matches no visible row")
    func primaryNoneVisible() {
        #expect(SongsRowResolver.primaryRow(in: visible, selection: [99]) == nil)
        #expect(SongsRowResolver.primaryRow(in: visible, selection: []) == nil)
    }

    @Test("orderedSelection preserves visible order and DROPS off-screen ids")
    func orderedDropsHidden() {
        // 40 & 20 are visible-selected; 99 is selected but not visible → dropped. Order = visible order.
        #expect(
            SongsRowResolver.orderedSelection(in: visible, selection: [40, 20, 99])
                == [Row(id: 20), Row(id: 40)]
        )
    }

    @Test("empty selection → empty ordered subset")
    func orderedEmpty() {
        #expect(SongsRowResolver.orderedSelection(in: visible, selection: []).isEmpty)
    }

    @Test("filtered subset: resolution honors the VISIBLE array, never a hidden row")
    func filteredSubset() {
        let filtered = [Row(id: 20), Row(id: 40)] // 10 & 30 hidden by an active filter
        // id 10 is selected but hidden → primaryRow skips it, returns the first VISIBLE selected (40).
        #expect(SongsRowResolver.primaryRow(in: filtered, selection: [10, 40]) == Row(id: 40))
        #expect(SongsRowResolver.orderedSelection(in: filtered, selection: [10, 40]) == [Row(id: 40)])
    }
}
