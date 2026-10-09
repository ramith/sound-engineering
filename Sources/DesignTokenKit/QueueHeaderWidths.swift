// QueueHeaderWidths — the Now Playing queue header's width policy (S10.8 D2), pure, so the app's
// `QueueHeaderLayout` and its unit tests share one rule (like LibraryBrowseKit's FillGridLayout).

import Foundation

/// How the queue header's parts share its width — the title, the count, the icon chips, the
/// Up Next / Recent switch and the filter pill, in their order:
///
/// 1. Every part but the count and the filter keeps its ideal width: a control label never
///    truncates.
/// 2. The filter compresses first, from its ideal width down to its minimum, which holds its whole
///    placeholder (SLOT-06).
/// 3. Then the count gives way. It is offered what is left and takes what its form needs —
///    `countTakes` answers for it (in the app, the view: its compact form, or truncation), so the
///    policy never sees its text. What it does not take goes back to the filter, up to its ideal.
/// 4. Where even the filter's minimum no longer fits beside the rest (large text), the filter
///    takes a row of its own under them, and the count has the first row's room to itself.
///
/// `requiredWidth` is the wider row: within `available` unless the first row's parts overflow on
/// their own — text far larger than the 880pt window was designed for.
public struct QueueHeaderWidths: Equatable, Sendable {
    /// Each part's width, in the order given.
    public let widths: [Double]
    /// The filter sits on a row of its own under the other parts.
    public let filterOnOwnRow: Bool
    /// The width the arrangement needs: the wider of its rows.
    public let requiredWidth: Double

    /// - Parameters:
    ///   - available: the row's width; `.infinity` asks for its ideal arrangement.
    ///   - spacing: the gap between neighbouring parts on a row.
    ///   - idealWidths: each part's ideal width, in order.
    ///   - count: the count's index in `idealWidths`, if there is one.
    ///   - filter: the filter's index in `idealWidths`, if there is one (the queue's History mode
    ///     has none).
    ///   - filterMinimum: the narrowest the filter gets.
    ///   - countTakes: the width the count takes when offered a width; offered `.infinity`, its
    ///     ideal.
    public init(available: Double, spacing: Double, idealWidths: [Double], count: Int?, filter: Int?,
                filterMinimum: Double, countTakes: (Double) -> Double) {
        var widths = idealWidths
        let fixed = idealWidths.indices.reduce(0.0) { total, index in
            index == count || index == filter ? total : total + idealWidths[index]
        }
        let countIdeal = count.map { idealWidths[$0] } ?? 0
        let filterRange = filter.map { filterMinimum ... max(idealWidths[$0], filterMinimum) }

        // The count's and the filter's room with every part on one row; short of the filter's
        // minimum, the filter moves to a row of its own.
        let oneRowRoom = available - Self.gaps(idealWidths.count, spacing) - fixed
        let ownRow = filterRange.map { oneRowRoom < $0.lowerBound } ?? false
        let firstRowParts = idealWidths.count - (ownRow ? 1 : 0)
        let room = available - Self.gaps(firstRowParts, spacing) - fixed

        if let count {
            // Whole while the filter can shrink to make room; past that, what the filter's minimum
            // leaves (or, the filter below, the whole first row's room).
            let spare = room - (ownRow ? 0 : (filterRange?.lowerBound ?? 0))
            widths[count] = spare >= countIdeal ? countTakes(.infinity) : countTakes(max(spare, 0))
        }
        if let filter, let filterRange {
            let rest = ownRow ? available : room - (count.map { widths[$0] } ?? 0)
            widths[filter] = min(max(rest, filterRange.lowerBound), filterRange.upperBound)
        }

        let firstRow = widths.indices.reduce(Self.gaps(firstRowParts, spacing)) { total, index in
            ownRow && index == filter ? total : total + widths[index]
        }
        let secondRow = ownRow ? (filter.map { widths[$0] } ?? 0) : 0
        self.widths = widths
        filterOnOwnRow = ownRow
        requiredWidth = max(firstRow, secondRow)
    }

    private static func gaps(_ parts: Int, _ spacing: Double) -> Double {
        spacing * Double(max(parts - 1, 0))
    }
}
