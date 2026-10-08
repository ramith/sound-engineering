import LibraryBrowseKit
import Testing

// MARK: - ListSelection's context-menu target (S10.8 E1 — the End-key hang)

/// SwiftUI builds a row's context menu with the row — for every row it builds — so the menu's choice
/// between "the selection" and "this row" must be O(1) and never walk the list.
@Suite("ListSelection — the context menu's target, O(1)")
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
        #expect(selection.menuActsOnSelection(clicked: 30))
    }

    @Test("a right-click acts on the clicked row alone: the only selected row, or an unselected one")
    func menuOnClickedRowAlone() {
        #expect(!clicked(20).menuActsOnSelection(clicked: 20)) // the selection IS the row
        var many = clicked(20)
        many.click(40, extend: true, toggle: false, in: rows)
        #expect(!many.menuActsOnSelection(clicked: 60)) // outside the selection
        #expect(!Selection().menuActsOnSelection(clicked: 10)) // nothing selected
    }

    @Test("the menu's target is read from the selection alone — no rows — so building a row stays O(1)")
    func menuTargetNeedsNoRows() {
        // The SIGNATURE is the guard: it takes no rows, so building a row's menu (SwiftUI builds it
        // with every row) can't scan the list. Exercised here on a 10,000-row selection.
        var selection = Selection()
        let many = Array(0 ..< 10000)
        selection.selectAll(in: many)
        #expect(selection.menuActsOnSelection(clicked: 9999))
        #expect(!selection.menuActsOnSelection(clicked: 10000))
    }
}
