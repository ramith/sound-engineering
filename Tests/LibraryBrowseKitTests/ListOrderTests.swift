import LibraryBrowseKit
import Testing

// MARK: - ListOrder (S10.8 E4 fix round — the store's reorder rule, in memory)

@Suite("ListOrder — listed rows first in the listed order, then the rest as they were")
struct ListOrderTests {
    private struct Row: Equatable {
        let id: Int
        let title: String
    }

    private let rows = ["a", "b", "c", "d"]

    @Test("a full order is taken as it is")
    func fullOrder() {
        #expect(ListOrder.applying(["d", "b", "a", "c"], to: rows, id: \.self) == ["d", "b", "a", "c"])
    }

    @Test("unlisted rows follow the listed ones, in their current order (an add during a move)")
    func unlistedRowsFollow() {
        #expect(ListOrder.applying(["c", "a"], to: rows, id: \.self) == ["c", "a", "b", "d"])
    }

    @Test("ids that aren't rows (a removed entry) and repeated ids are ignored")
    func foreignAndRepeatedIDs() {
        #expect(ListOrder.applying(["c", "zz", "c", "a"], to: rows, id: \.self) == ["c", "a", "b", "d"])
    }

    @Test("no order leaves the rows as they are; no rows stay none")
    func emptyInputs() {
        #expect(ListOrder.applying([String](), to: rows, id: \.self) == rows)
        #expect(ListOrder.applying(["a"], to: [String](), id: \.self).isEmpty)
    }

    @Test("rows are moved whole, by their id")
    func rowsMoveWhole() {
        let rows = [Row(id: 1, title: "one"), Row(id: 2, title: "two"), Row(id: 3, title: "three")]
        #expect(ListOrder.applying([3, 1], to: rows, id: \.id) == [rows[2], rows[0], rows[1]])
    }

    @Test("every row appears exactly once, for any order over the rows and strangers")
    func everyRowOnce() {
        let candidates = ["d", "zz", "a", "c", "a", "b"]
        for mask in 0 ..< (1 << candidates.count) {
            let order = candidates.indices.filter { mask & (1 << $0) != 0 }.map { candidates[$0] }
            let result = ListOrder.applying(order, to: rows, id: \.self)
            #expect(result.sorted() == rows, "\(order)")
        }
    }

    @Test("it agrees with ListMove: a planned order applied to the rows is that order")
    func agreesWithListMove() {
        for move in ListMove.allCases {
            for row in rows {
                guard let order = move.reordering(rows, moving: [row]) else { continue }
                #expect(ListOrder.applying(order, to: rows, id: \.self) == order)
            }
        }
    }
}
