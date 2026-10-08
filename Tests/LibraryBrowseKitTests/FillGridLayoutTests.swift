import LibraryBrowseKit
import Testing

// MARK: - FillGridLayout (S10.8 D5 — the browse grid's fill-width columns)

@Suite("FillGridLayout — fill-width columns of at least 160 pt, at least two")
struct FillGridLayoutTests {
    /// The browse grid: 160-pt minimum tiles, 12-pt gaps, at least two columns. `area` is the grid
    /// area's width; the tiles share it less the 12-pt side insets — `max(2, ⌊(W − 24 + 12) / 172⌋)`.
    private func layout(area: Double) -> FillGridLayout {
        FillGridLayout(width: area - 24, minimumTile: 160, spacing: 12, minimumColumns: 2)
    }

    @Test("the design's windows: 880 → 3 columns, 1000 → 4, 1440 → 6")
    func designWindows() {
        // The Library card at each window width: less 2 × 22 insets, the 234-pt rail and the 20-pt gap.
        #expect(layout(area: 880 - 44 - 234 - 20).columns == 3)
        #expect(layout(area: 1000 - 44 - 234 - 20).columns == 4)
        #expect(layout(area: 1440 - 44 - 234 - 20).columns == 6)
    }

    @Test("the tiles fill the width exactly: n tiles plus n − 1 gaps")
    func tilesFillTheWidth() {
        for area in stride(from: 300.0, through: 2400, by: 37) {
            let grid = layout(area: area)
            let used = Double(grid.columns) * grid.tileWidth + 12 * Double(grid.columns - 1)
            #expect(abs(used - (area - 24)) < 0.000_1, "area \(area): \(used)")
            #expect(grid.tileWidth >= 160 || grid.columns == 2, "area \(area): \(grid.tileWidth)")
        }
    }

    @Test("at 880 × 640 a tile is 178 pt, its art 162 (the design's numbers)")
    func minimumWindowTile() {
        #expect(layout(area: 582).tileWidth == 178)
    }

    @Test("a column appears exactly when one more 160-pt tile fits")
    func columnBoundaries() {
        #expect(layout(area: 24 + 675.5).columns == 3) // 4 × 160 + 3 × 12 = 676
        #expect(layout(area: 24 + 676).columns == 4)
        #expect(layout(area: 24 + 676).tileWidth == 160)
    }

    @Test("never fewer than two columns, however narrow")
    func atLeastTwoColumns() {
        let narrow = layout(area: 124)
        #expect(narrow.columns == 2)
        #expect(narrow.tileWidth == 44)
    }

    @Test("unmeasured or nonsense widths: two columns of nothing")
    func degenerateWidths() {
        for width in [0.0, -50, .nan] {
            let grid = FillGridLayout(width: width, minimumTile: 160, spacing: 12, minimumColumns: 2)
            #expect(grid.columns == 2)
            #expect(grid.tileWidth == 0)
        }
    }
}
