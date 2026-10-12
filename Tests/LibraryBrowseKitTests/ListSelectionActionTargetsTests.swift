import LibraryBrowseKit
import Testing

// MARK: - ListSelection's keyboard-verb targets (S10.8 E — ⌘↩ Play Next, ⇧⌘↩ Add to Queue, ⌘I Info)

/// The row menu's verbs from the keys act on the selection, or else the cursor row — under Return's
/// rule, so a verb never acts on a row nothing on screen marks.
@Suite("ListSelection — what a keyboard verb acts on")
struct ListSelectionActionTargetsTests {
    private typealias Selection = ListSelection<Int>
    private let rows = [10, 20, 30, 40, 50, 60]

    @Test("the selected rows, in DISPLAY order — whatever order they were chosen in")
    func selectionInDisplayOrder() {
        var selection = Selection()
        selection.click(50, extend: false, toggle: false, in: rows)
        selection.click(20, extend: false, toggle: true, in: rows)
        selection.click(40, extend: false, toggle: true, in: rows)
        #expect(selection.actionTargets(in: rows, ringVisible: false) == [20, 40, 50])
        #expect(selection.actionTargets(in: rows.reversed(), ringVisible: true) == [50, 40, 20])
    }

    @Test("a selected row the list no longer shows is not a target")
    func hiddenSelectionIsNotATarget() {
        var selection = Selection()
        selection.selectAll(in: rows)
        #expect(selection.actionTargets(in: [20, 30, 99], ringVisible: false) == [20, 30])
    }

    @Test("with nothing selected: the cursor row while its ring is drawn, nothing while it is not")
    func cursorRowWhenNothingSelected() {
        let fresh = Selection() // an unanchored cursor on the first row
        #expect(fresh.actionTargets(in: rows, ringVisible: true) == [10])
        #expect(fresh.actionTargets(in: rows, ringVisible: false).isEmpty)

        var cleared = Selection()
        cleared.click(40, extend: false, toggle: false, in: rows)
        cleared.clear() // Esc: nothing selected, the ring stays on 40
        #expect(cleared.actionTargets(in: rows, ringVisible: true) == [40])
        #expect(cleared.actionTargets(in: rows, ringVisible: false).isEmpty)
    }

    @Test("an empty list has no target")
    func emptyList() {
        #expect(Selection().actionTargets(in: [Int](), ringVisible: true).isEmpty)
    }
}
