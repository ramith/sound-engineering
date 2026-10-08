import LibraryBrowseKit
import Testing

// MARK: - GridCursorState (S10.8 decision 20 — what a browse grid's keyboard remembers)

@Suite("GridCursorState — the anchor, and the type-to-select prefix every other move ends")
struct GridCursorStateTests {
    private struct Album: Identifiable {
        let id: Int
        let title: String
    }

    /// Two to a row:  ABBA · Beatles / Bob Marley · Oasis / Queen
    private let albums = [
        Album(id: 1, title: "ABBA"), Album(id: 2, title: "Beatles"), Album(id: 3, title: "Bob Marley"),
        Album(id: 4, title: "Oasis"), Album(id: 5, title: "Queen"),
    ]
    private var ids: [Int] {
        albums.map(\.id)
    }

    private let start = ContinuousClock.now

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    private func type(_ text: String, at seconds: Double, into state: inout GridCursorState<Int>) -> Int? {
        state.typeSelect(text, at: at(seconds), in: albums, title: \.title)
    }

    // MARK: The anchor

    @Test("no anchor yet: the cursor is the first tile, unanchored")
    func noAnchor() {
        let state = GridCursorState<Int>()
        #expect(state.anchor == nil)
        #expect(state.cursor(in: ids, columns: 2)?.id == 1)
    }

    @Test("a navigation key anchors the tile it lands on; one that bubbles changes nothing")
    func moveAnchors() {
        var state = GridCursorState<Int>()
        state.choose(2)
        #expect(state.move(.down, in: ids, columns: 2) == 4)
        #expect(state.anchor == 4)
        #expect(state.move(.right, in: [4], columns: 2) == nil) // off the end: bubbles
        #expect(state.anchor == 4)
    }

    @Test("type-select anchors the first title with the prefix; a miss keeps the anchor")
    func typeSelectAnchors() {
        var state = GridCursorState<Int>()
        #expect(type("b", at: 0, into: &state) == 2)
        #expect(type("o", at: 0.3, into: &state) == 3) // "bo" → Bob Marley
        #expect(state.anchor == 3)
        #expect(type("x", at: 0.5, into: &state) == nil) // "box" → nothing
        #expect(state.anchor == 3)
    }

    // MARK: The prefix ends with any other cursor change (review MINOR)

    @Test("\"b\", →, \"o\" within a second searches \"o\", not \"bo\"")
    func arrowEndsThePrefix() {
        var state = GridCursorState<Int>()
        #expect(type("b", at: 0, into: &state) == 2)
        #expect(state.move(.right, in: ids, columns: 2) == 3)
        #expect(type("o", at: 0.3, into: &state) == 4) // Oasis — "bo" would stay on Bob Marley
    }

    @Test("opening a tile, or the cursor a return brings back, ends the prefix")
    func chooseEndsThePrefix() {
        var state = GridCursorState<Int>()
        #expect(type("b", at: 0, into: &state) == 2)
        state.choose(5)
        #expect(type("o", at: 0.3, into: &state) == 4)
    }

    @Test("losing focus ends the prefix and keeps the anchor")
    func focusLossEndsThePrefix() {
        var state = GridCursorState<Int>()
        #expect(type("b", at: 0, into: &state) == 2)
        state.endTyping()
        #expect(state.anchor == 2)
        #expect(type("o", at: 0.3, into: &state) == 4)
    }
}
