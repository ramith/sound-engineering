import LibraryBrowseKit
import Testing

// MARK: - GridLayoutMath (S10.8 decision 20 — the grid arithmetic the keys need)

@Suite("GridLayoutMath — columns, page size and row pitch")
struct GridLayoutMathTests {
    /// Today's browse grid: 168-pt tiles, 16-pt column gaps.
    private func columns(_ width: Double) -> Int {
        GridLayoutMath.adaptiveColumns(width: width, minimum: 168, spacing: 16)
    }

    @Test("as many minimum-wide tiles as fit with the gaps between them")
    func adaptiveColumns() {
        #expect(columns(168) == 1)
        #expect(columns(352) == 2) // 2 × 168 + 16
        #expect(columns(536) == 3)
        #expect(columns(968) == 5) // a 1000-pt grid less its 16-pt insets
    }

    @Test("a column appears exactly at its boundary, not a fraction before (SwiftUI's adaptive rule)")
    func columnBoundaries() {
        #expect(columns(351.75) == 1)
        #expect(columns(352) == 2)
        #expect(columns(719.5) == 3)
        #expect(columns(720) == 4)
    }

    @Test("too narrow, unmeasured or nonsense widths still give one column")
    func atLeastOneColumn() {
        #expect(columns(100) == 1)
        #expect(columns(0) == 1)
        #expect(columns(-50) == 1)
        #expect(columns(.nan) == 1)
        #expect(columns(.infinity) == 1000) // the sanity cap
    }

    @Test("a page is the whole rows the viewport shows, at least one")
    func rowsPerPage() {
        #expect(GridLayoutMath.rowsPerPage(viewportHeight: 600, rowPitch: 256) == 2)
        #expect(GridLayoutMath.rowsPerPage(viewportHeight: 768, rowPitch: 256) == 3)
        #expect(GridLayoutMath.rowsPerPage(viewportHeight: 200, rowPitch: 256) == 1)
        #expect(GridLayoutMath.rowsPerPage(viewportHeight: 600, rowPitch: 24) == 25) // a list
    }

    @Test("no pitch or viewport yet: a page is one row")
    func rowsPerPageUnmeasured() {
        #expect(GridLayoutMath.rowsPerPage(viewportHeight: 600, rowPitch: 0) == 1)
        #expect(GridLayoutMath.rowsPerPage(viewportHeight: 0, rowPitch: 256) == 1)
        #expect(GridLayoutMath.rowsPerPage(viewportHeight: .nan, rowPitch: 256) == 1)
    }

    @Test("the row pitch is the smallest gap between two different tops (one row shares a top)")
    func rowPitch() {
        #expect(GridLayoutMath.rowPitch(tops: [528, 16, 272, 16, 272, 16]) == 256)
        #expect(GridLayoutMath.rowPitch(tops: [4, 28, 52]) == 24) // list rows
        #expect(GridLayoutMath.rowPitch(tops: [16, 16.0001, 272]) == 256) // float noise is one top
    }

    @Test("fewer than two rows laid out: no pitch yet")
    func rowPitchNeedsTwoRows() {
        #expect(GridLayoutMath.rowPitch(tops: [16, 16, 16]) == nil)
        #expect(GridLayoutMath.rowPitch(tops: []) == nil)
    }
}
