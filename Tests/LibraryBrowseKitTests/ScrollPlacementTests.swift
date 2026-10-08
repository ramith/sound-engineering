import LibraryBrowseKit
import Testing

// MARK: - ScrollPlacement (S10.8 D6 + decision 20 — where a scroll puts a tile)

@Suite("ScrollPlacement — the restore point and scroll-into-view")
struct ScrollPlacementTests {
    private typealias Tile = ScrollPlacement.Tile<Int>

    /// Today's tile (232 pt tall with its labels) in a 600-pt viewport.
    private let height = 232.0
    private let viewport = 600.0

    /// Where `scrollTo(_:anchor:)` puts an item's top for an anchor `y` (measured offscreen).
    private func landedTop(anchorY: Double, viewport: Double = 600) -> Double {
        anchorY * (viewport - height)
    }

    private func tile(_ id: Int, top: Double, leading: Double = 16) -> Tile {
        Tile(id: id, top: top, leading: leading, height: height)
    }

    // MARK: restorePoint (D6)

    @Test("the cursor tile, fully visible, is the pin — and comes back at exactly the same height")
    func cursorPinsExactly() throws {
        let tiles = [tile(1, top: -120), tile(5, top: 110.5), tile(6, top: 110.5, leading: 200)]
        let point = try #require(ScrollPlacement.restorePoint(tiles: tiles, viewportHeight: viewport, preferred: 6))
        #expect(point.id == 6)
        #expect(abs(landedTop(anchorY: point.anchorY) - 110.5) < 0.000_1)
    }

    @Test("a cursor tile cut off by an edge yields to the first fully visible tile, in reading order")
    func partlyHiddenCursorYields() throws {
        let tiles = [tile(1, top: -120), tile(9, top: 400), tile(6, top: 110, leading: 200), tile(5, top: 110)]
        let point = try #require(ScrollPlacement.restorePoint(tiles: tiles, viewportHeight: viewport, preferred: 9))
        #expect(point.id == 5) // top row first, then leading
        #expect(abs(landedTop(anchorY: point.anchorY) - 110) < 0.000_1)
    }

    @Test("no cursor: the first fully visible tile pins the position")
    func noCursor() throws {
        let tiles = [tile(4, top: 300), tile(2, top: 44)]
        let point = try #require(ScrollPlacement.restorePoint(tiles: tiles, viewportHeight: viewport, preferred: nil))
        #expect(point.id == 2)
    }

    @Test("nothing fully visible (a viewport shorter than a tile): the tile nearest the top, shown from its top")
    func nothingFullyVisible() throws {
        let tiles = [tile(3, top: -150), tile(7, top: 40)]
        let point = try #require(ScrollPlacement.restorePoint(tiles: tiles, viewportHeight: 200, preferred: 3))
        #expect(point.id == 7)
        #expect(point.anchorY == 0)
    }

    @Test("only a tile cut off at the top is laid out: it comes back from its top, never above the viewport")
    func cutOffTileClampsToTop() throws {
        let point = try #require(ScrollPlacement.restorePoint(tiles: [tile(3, top: -100)], viewportHeight: 300,
                                                              preferred: nil))
        #expect(point.id == 3)
        #expect(point.anchorY == 0)
    }

    @Test("nothing laid out: no restore point")
    func emptyRestore() {
        #expect(ScrollPlacement.restorePoint(tiles: [Tile](), viewportHeight: viewport, preferred: 1) == nil)
    }

    @Test("a window resized in between: the pinned tile comes back at the same relative height")
    func resizeKeepsRelativeHeight() throws {
        let point = try #require(ScrollPlacement.restorePoint(tiles: [tile(5, top: 184)], viewportHeight: viewport,
                                                              preferred: 5))
        #expect(point.anchorY == 0.5) // half-way down the room the tile can travel
        #expect(landedTop(anchorY: point.anchorY, viewport: 500) == 134) // half-way down the shorter window
    }

    // MARK: revealAnchorY (scroll-into-view)

    @Test("a tile fully visible with room for its ring: no scroll")
    func visibleNoScroll() {
        let anchor = ScrollPlacement.revealAnchorY(top: 100, itemHeight: height, viewportHeight: viewport,
                                                   margin: 8, forward: true)
        #expect(anchor == nil)
    }

    @Test("flush against an edge (its ring would be cut): scrolls it the margin inside")
    func flushScrolls() throws {
        let atTop = try #require(ScrollPlacement.revealAnchorY(top: 0, itemHeight: height, viewportHeight: viewport,
                                                               margin: 8, forward: false))
        #expect(abs(landedTop(anchorY: atTop) - 8) < 0.000_1)
        let atBottom = try #require(ScrollPlacement.revealAnchorY(top: 368, itemHeight: height,
                                                                  viewportHeight: viewport, margin: 8, forward: true))
        #expect(abs(landedTop(anchorY: atBottom) - 360) < 0.000_1)
    }

    @Test("partly off the top or bottom: brought in at the nearer edge, whatever the direction of travel")
    func partlyOff() throws {
        let above = try #require(ScrollPlacement.revealAnchorY(top: -100, itemHeight: height, viewportHeight: viewport,
                                                               margin: 8, forward: true))
        #expect(abs(landedTop(anchorY: above) - 8) < 0.000_1)
        let below = try #require(ScrollPlacement.revealAnchorY(top: 500, itemHeight: height, viewportHeight: viewport,
                                                               margin: 8, forward: false))
        #expect(abs(landedTop(anchorY: below) - 360) < 0.000_1)
    }

    @Test("not laid out (far off screen): the direction of travel picks the edge")
    func notLaidOut() throws {
        let forward = try #require(ScrollPlacement.revealAnchorY(top: nil, itemHeight: height,
                                                                 viewportHeight: viewport, margin: 8, forward: true))
        #expect(abs(landedTop(anchorY: forward) - 360) < 0.000_1)
        let back = try #require(ScrollPlacement.revealAnchorY(top: nil, itemHeight: height, viewportHeight: viewport,
                                                              margin: 8, forward: false))
        #expect(abs(landedTop(anchorY: back) - 8) < 0.000_1)
    }

    @Test("a tile taller than the viewport is shown from its top")
    func tallerThanViewport() {
        let anchor = ScrollPlacement.revealAnchorY(top: 50, itemHeight: height, viewportHeight: 200,
                                                   margin: 8, forward: true)
        #expect(anchor == 0)
    }
}
