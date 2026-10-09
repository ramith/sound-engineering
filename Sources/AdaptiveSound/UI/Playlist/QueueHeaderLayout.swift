import DesignTokenKit
import SwiftUI

// MARK: - Queue header layout (S10.8 D2 — the header row's width policy, in code)

/// The Now Playing queue header (`png/03`): the title, the count, the icon chips and the
/// Up Next / Recent switch from the leading edge, the filter pill at the trailing edge.
///
/// An `HStack` could not hold the row's width-deficit policy: it offered the count its whole width
/// before it reserved the filter's minimum, so at the 880pt window the row ran 16pt wider than the
/// queue column and pushed the whole Now Playing tab past the window. The policy is Kit data,
/// `QueueHeaderWidths` (unit-tested at the design's widths, every count size, History mode and
/// large text); this layout measures the parts, asks it, and places them:
///
/// - the title, chips and switch keep their ideal widths; the filter compresses first, then the
///   count gives way (its compact form, then truncation) and what it doesn't take goes back to the
///   filter;
/// - where even the filter's minimum no longer fits beside the rest — larger text — the filter
///   takes a row of its own under the others, at the trailing edge, rather than overlapping them
///   or pushing the column wider. A `.dynamicTypeSize` clamp could not prevent that: on macOS 26
///   text styles do not follow the Dynamic Type environment, so a clamp bounds nothing — the
///   layout has to hold at any size.
///
/// Every part is centred on its row; the header is as tall as its rows.
struct QueueHeaderLayout: Layout {
    /// What a part does when the row runs short of width.
    enum Role {
        case rigid, count, filter
    }

    var spacing: CGFloat
    /// The gap above the filter when it takes its own row.
    var rowSpacing: CGFloat = DesignSystem.Spacing.small

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let available = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let plan = plan(in: available ?? .infinity, subviews: subviews)
        let rows = rowHeights(plan, subviews: subviews)
        // Wider than offered only when the first row's parts overflow on their own.
        let width = max(available ?? 0, CGFloat(plan.requiredWidth))
        return CGSize(width: width, height: rows.first + (rows.filter.map { rowSpacing + $0 } ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let plan = plan(in: bounds.width, subviews: subviews)
        let rows = rowHeights(plan, subviews: subviews)
        let firstRowY = rows.filter == nil ? bounds.midY : bounds.minY + rows.first / 2
        let filter = index(of: .filter, in: subviews)
        var x = bounds.minX
        for (position, subview) in subviews.enumerated() {
            let width = CGFloat(plan.widths[position])
            let proposal = ProposedViewSize(width: width, height: nil)
            if position == filter {
                let y = rows.filter.map { bounds.minY + rows.first + rowSpacing + $0 / 2 } ?? firstRowY
                subview.place(at: CGPoint(x: bounds.maxX - width, y: y), anchor: .leading, proposal: proposal)
            } else {
                subview.place(at: CGPoint(x: x, y: firstRowY), anchor: .leading, proposal: proposal)
                x += width + spacing
            }
        }
    }
}

extension QueueHeaderLayout {
    /// A part's role, set by `queueHeaderRole(_:)`; a part without one is rigid.
    struct RoleKey: LayoutValueKey {
        static let defaultValue = Role.rigid
    }

    /// The Kit policy, fed with the parts' measured widths; the count answers for itself.
    private func plan(in width: CGFloat, subviews: Subviews) -> QueueHeaderWidths {
        let count = index(of: .count, in: subviews)
        let filter = index(of: .filter, in: subviews)
        let filterMinimum = filter.map { subviews[$0].sizeThatFits(ProposedViewSize(width: 0, height: nil)).width }
        return QueueHeaderWidths(
            available: Double(width),
            spacing: Double(spacing),
            idealWidths: subviews.map { Double($0.sizeThatFits(.unspecified).width) },
            count: count,
            filter: filter,
            filterMinimum: Double(filterMinimum ?? 0)
        ) { offer in
            guard let count else { return 0 }
            let proposal = ProposedViewSize(width: offer.isFinite ? CGFloat(offer) : nil, height: nil)
            return Double(subviews[count].sizeThatFits(proposal).width)
        }
    }

    /// The first row's height, and the filter's row's when it has one.
    private func rowHeights(_ plan: QueueHeaderWidths, subviews: Subviews) -> (first: CGFloat, filter: CGFloat?) {
        let filter = plan.filterOnOwnRow ? index(of: .filter, in: subviews) : nil
        var first: CGFloat = 0
        var filterRow: CGFloat?
        for (position, subview) in subviews.enumerated() {
            let proposal = ProposedViewSize(width: CGFloat(plan.widths[position]), height: nil)
            let height = subview.sizeThatFits(proposal).height
            if position == filter {
                filterRow = height
            } else {
                first = max(first, height)
            }
        }
        return (first, filterRow)
    }

    /// The first part with `role`.
    private func index(of role: Role, in subviews: Subviews) -> Int? {
        subviews.firstIndex { $0[RoleKey.self] == role }
    }
}

extension View {
    /// This part's role in `QueueHeaderLayout`; a part without one is rigid.
    func queueHeaderRole(_ role: QueueHeaderLayout.Role) -> some View {
        layoutValue(key: QueueHeaderLayout.RoleKey.self, value: role)
    }
}
