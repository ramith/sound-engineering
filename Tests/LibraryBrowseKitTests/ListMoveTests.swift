import LibraryBrowseKit
import Testing

// MARK: - ListMove (S10.8 E4 — the playlist's Move Up / Down / to Top / to Bottom)

@Suite("ListMove — the selection moves as one block, keeps its order, and stops at the edges")
struct ListMoveTests {
    private let rows = ["a", "b", "c", "d", "e"]

    // MARK: one row

    @Test("one row moves one place up or down, or to either end")
    func singleRow() {
        #expect(ListMove.up.reordering(rows, moving: ["c"]) == ["a", "c", "b", "d", "e"])
        #expect(ListMove.down.reordering(rows, moving: ["c"]) == ["a", "b", "d", "c", "e"])
        #expect(ListMove.toTop.reordering(rows, moving: ["c"]) == ["c", "a", "b", "d", "e"])
        #expect(ListMove.toBottom.reordering(rows, moving: ["c"]) == ["a", "b", "d", "e", "c"])
    }

    @Test("the first row can't go up and the last can't go down — but each can go the other way")
    func singleRowEdges() {
        #expect(ListMove.up.reordering(rows, moving: ["a"]) == nil)
        #expect(ListMove.toTop.reordering(rows, moving: ["a"]) == nil)
        #expect(ListMove.down.reordering(rows, moving: ["a"]) == ["b", "a", "c", "d", "e"])
        #expect(ListMove.toBottom.reordering(rows, moving: ["a"]) == ["b", "c", "d", "e", "a"])

        #expect(ListMove.down.reordering(rows, moving: ["e"]) == nil)
        #expect(ListMove.toBottom.reordering(rows, moving: ["e"]) == nil)
        #expect(ListMove.up.reordering(rows, moving: ["e"]) == ["a", "b", "c", "e", "d"])
        #expect(ListMove.toTop.reordering(rows, moving: ["e"]) == ["e", "a", "b", "c", "d"])
    }

    @Test("the next-to-edge row reaches the edge in one step (no off-by-one past it)")
    func nextToEdge() {
        #expect(ListMove.up.reordering(rows, moving: ["b"]) == ["b", "a", "c", "d", "e"])
        #expect(ListMove.down.reordering(rows, moving: ["d"]) == ["a", "b", "c", "e", "d"])
    }

    @Test("a one-row list has nowhere to go; an empty list has nothing to move")
    func tinyLists() {
        for move in ListMove.allCases {
            #expect(move.reordering(["a"], moving: ["a"]) == nil)
            #expect(move.reordering([String](), moving: ["a"]) == nil)
        }
    }

    // MARK: a block

    @Test("a contiguous block moves together, one place or to either end, in its own order")
    func contiguousBlock() {
        let block: Set = ["b", "c"]
        #expect(ListMove.up.reordering(rows, moving: block) == ["b", "c", "a", "d", "e"])
        #expect(ListMove.down.reordering(rows, moving: block) == ["a", "d", "b", "c", "e"])
        #expect(ListMove.toTop.reordering(rows, moving: block) == ["b", "c", "a", "d", "e"])
        #expect(ListMove.toBottom.reordering(rows, moving: block) == ["a", "d", "e", "b", "c"])
    }

    @Test("a block against an edge can't move further that way")
    func blockAtEdges() {
        #expect(ListMove.up.reordering(rows, moving: ["a", "b"]) == nil)
        #expect(ListMove.toTop.reordering(rows, moving: ["a", "b"]) == nil)
        #expect(ListMove.down.reordering(rows, moving: ["d", "e"]) == nil)
        #expect(ListMove.toBottom.reordering(rows, moving: ["d", "e"]) == nil)
        #expect(ListMove.down.reordering(rows, moving: ["a", "b"]) == ["c", "a", "b", "d", "e"])
        #expect(ListMove.up.reordering(rows, moving: ["d", "e"]) == ["a", "b", "d", "e", "c"])
    }

    @Test("the whole list selected can't move at all")
    func everythingSelected() {
        for move in ListMove.allCases {
            #expect(move.reordering(rows, moving: Set(rows)) == nil)
        }
    }

    @Test("a scattered selection gathers into one block, in order, one place beyond its leading row")
    func scatteredSelectionGathers() {
        let scattered: Set = ["b", "d"]
        #expect(ListMove.up.reordering(rows, moving: scattered) == ["b", "d", "a", "c", "e"])
        #expect(ListMove.down.reordering(rows, moving: scattered) == ["a", "c", "e", "b", "d"])
        #expect(ListMove.toTop.reordering(rows, moving: scattered) == ["b", "d", "a", "c", "e"])
        #expect(ListMove.toBottom.reordering(rows, moving: scattered) == ["a", "c", "e", "b", "d"])
    }

    @Test("a scattered selection touching an edge still gathers against it — it isn't 'at the edge' yet")
    func scatteredAtEdgeGathers() {
        #expect(ListMove.up.reordering(rows, moving: ["a", "c"]) == ["a", "c", "b", "d", "e"])
        #expect(ListMove.toTop.reordering(rows, moving: ["a", "c"]) == ["a", "c", "b", "d", "e"])
        #expect(ListMove.down.reordering(rows, moving: ["c", "e"]) == ["a", "b", "d", "c", "e"])
        #expect(ListMove.toBottom.reordering(rows, moving: ["c", "e"]) == ["a", "b", "d", "c", "e"])
    }

    // MARK: the selection's ids

    @Test("ids that aren't rows are ignored; nothing selected (or nothing found) is no move")
    func foreignIDs() {
        #expect(ListMove.up.reordering(rows, moving: ["c", "zz"]) == ["a", "c", "b", "d", "e"])
        for move in ListMove.allCases {
            #expect(move.reordering(rows, moving: []) == nil)
            #expect(move.reordering(rows, moving: ["zz"]) == nil)
        }
    }

    // MARK: held key

    @Test("a held Move Down walks one row to the bottom, one place per press, then stops")
    func heldKeyWalksToTheEdge() {
        var order = rows
        var landings: [Int] = []
        for _ in 0 ..< rows.count * 2 { // bounded: a planner that never says "edge" must fail, not hang
            guard let next = ListMove.down.reordering(order, moving: ["a"]) else { break }
            order = next
            landings.append(order.firstIndex(of: "a") ?? -1)
        }
        #expect(landings == [1, 2, 3, 4])
        #expect(order == ["b", "c", "d", "e", "a"])
    }

    // MARK: every selection of a small list

    @Test("for every selection: a permutation, both groups keep their order, one contiguous block")
    func everySelection() {
        for mask in 0 ..< (1 << rows.count) {
            let selection = Set(rows.indices.filter { mask & (1 << $0) != 0 }.map { rows[$0] })
            for move in ListMove.allCases {
                guard let moved = move.reordering(rows, moving: selection) else { continue }
                #expect(moved.sorted() == rows, "\(move) \(selection): not a permutation")
                #expect(moved.filter(selection.contains) == rows.filter(selection.contains))
                #expect(moved.filter { !selection.contains($0) } == rows.filter { !selection.contains($0) })
                let positions = moved.indices.filter { selection.contains(moved[$0]) }
                #expect(positions.last.map { $0 - positions[0] + 1 } == positions.count,
                        "\(move) \(selection): the block is not contiguous")
                #expect(moved != rows, "\(move) \(selection): an available move changed nothing")
            }
        }
    }

    @Test("the menu's cheap availability check agrees with the planner for every selection")
    func availabilityAgreesWithPlanner() {
        for mask in 0 ..< (1 << rows.count) {
            let positions = rows.indices.filter { mask & (1 << $0) != 0 }
            let selection = Set(positions.map { rows[$0] })
            for move in ListMove.allCases {
                #expect(move.isAvailable(forRowsAt: positions, count: rows.count)
                    == (move.reordering(rows, moving: selection) != nil), "\(move) \(selection)")
            }
        }
    }

    @Test("availability for one row: up and to-top off the first row, down and to-bottom off the last")
    func singleRowAvailability() {
        #expect(!ListMove.up.isAvailable(forRowsAt: CollectionOfOne(0), count: 5))
        #expect(!ListMove.toTop.isAvailable(forRowsAt: CollectionOfOne(0), count: 5))
        #expect(ListMove.down.isAvailable(forRowsAt: CollectionOfOne(0), count: 5))
        #expect(!ListMove.down.isAvailable(forRowsAt: CollectionOfOne(4), count: 5))
        #expect(!ListMove.toBottom.isAvailable(forRowsAt: CollectionOfOne(4), count: 5))
        #expect(ListMove.up.isAvailable(forRowsAt: CollectionOfOne(4), count: 5))
        #expect(!ListMove.up.isAvailable(forRowsAt: [Int](), count: 5))
    }
}
