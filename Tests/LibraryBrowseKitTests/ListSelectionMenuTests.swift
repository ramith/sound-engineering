import LibraryBrowseKit
import Testing

// MARK: - ListSelection's context-menu target (S10.8 E1; decided when an item is chosen, E break-it 10)

/// A row's menu acts on the selection only when the clicked row is one of SEVERAL selected rows on
/// screen; else on the clicked row alone. The decision walks the rows, so it runs when an item is
/// chosen — a list builds each row's menu with the row, for every row it builds (the End-key hang).
@Suite("ListSelection — the context menu's target")
struct ListSelectionMenuTests {
    private typealias Selection = ListSelection<Int>
    private let rows = [10, 20, 30, 40, 50, 60]

    /// A selection made by clicking `id`.
    private func clicked(_ id: Int) -> Selection {
        var selection = Selection()
        selection.click(id, extend: false, toggle: false, in: rows)
        return selection
    }

    @Test("a right-click on one of several selected rows acts on the selection")
    func menuOnSelectedRowOfMany() {
        var selection = clicked(20)
        selection.click(40, extend: true, toggle: false, in: rows)
        #expect(selection.menuActsOnSelection(clicked: 30, in: rows))
    }

    @Test("a right-click acts on the clicked row alone: the only selected row, or an unselected one")
    func menuOnClickedRowAlone() {
        #expect(!clicked(20).menuActsOnSelection(clicked: 20, in: rows)) // the selection IS the row
        var many = clicked(20)
        many.click(40, extend: true, toggle: false, in: rows)
        #expect(!many.menuActsOnSelection(clicked: 60, in: rows)) // outside the selection
        #expect(!Selection().menuActsOnSelection(clicked: 10, in: rows)) // nothing selected
    }

    @Test("a selected row a filter or a reload hid doesn't count: one shown is the clicked row alone")
    func hiddenSelectionDoesNotCount() {
        var selection = clicked(20)
        selection.click(40, extend: false, toggle: true, in: rows) // 20 and 40 selected
        #expect(selection.menuActsOnSelection(clicked: 20, in: rows))
        #expect(!selection.menuActsOnSelection(clicked: 20, in: [10, 20, 30])) // 40 hidden
        #expect(selection.menuActsOnSelection(clicked: 20, in: [40, 20])) // both shown, any order
    }

    @Test("the decision stops at the second shown selected row — cheap even over a long list")
    func decisionStopsEarly() {
        var selection = Selection()
        let many = Array(0 ..< 10000)
        selection.selectAll(in: many)
        #expect(selection.menuActsOnSelection(clicked: 9999, in: many))
        #expect(!selection.menuActsOnSelection(clicked: 10000, in: many)) // not selected
    }
}
