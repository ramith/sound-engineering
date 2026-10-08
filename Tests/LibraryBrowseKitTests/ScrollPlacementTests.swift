import LibraryBrowseKit
import Testing

// MARK: - ScrollPlacement (S10.8 decision 20 — where a scroll puts a tile)

@Suite("ScrollPlacement — scroll-into-view")
struct ScrollPlacementTests {
    /// Today's tile (232 pt tall with its labels) in a 600-pt viewport.
    private let height = 232.0
    private let viewport = 600.0

    /// Where `scrollTo(_:anchor:)` puts an item's top for an anchor `y` (measured offscreen).
    private func landedTop(anchorY: Double) -> Double {
        anchorY * (viewport - height)
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
