import SwiftUI

// MARK: - Queue header layout (S10.8 D2 — the header row's width policy, in code)

/// The Now Playing queue header's one row (`png/03`): the title, the count, the icon chips and the
/// Up Next / Recent switch from the leading edge, the filter pill at the trailing edge.
///
/// The row is too full for an `HStack` at the 880pt window: the stack offered the count its whole
/// width before it reserved the filter's minimum, so the row ran 16pt wider than the queue column
/// and pushed the whole Now Playing tab past the window (its 16pt insets read 8pt). This layout
/// states the width-deficit policy (break-it finding 2) instead:
///
/// 1. A `.rigid` part — the title, the chips, the switch — always gets its ideal width: a control
///    label never truncates.
/// 2. The `.filter` compresses first, from its ideal width down to its minimum, which holds its
///    whole placeholder (SLOT-06).
/// 3. Then the `.count` gives way — the designated truncation victim, which switches to its compact
///    form (`ViewThatFits`) before it would truncate. What the compact form does not use goes back
///    to the filter, up to its ideal width.
///
/// Space left over opens between the switch and the filter. Every part is centred vertically; the
/// row is as tall as its tallest part. One count and one filter: any further part marked either
/// way is laid out as rigid.
struct QueueHeaderLayout: Layout {
    /// What a part does when the row runs short of width.
    enum Role {
        case rigid, count, filter
    }

    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width: CGFloat = if let proposed = proposal.width, proposed.isFinite {
            // Never narrower than the rigid parts and the filter's minimum: past that the row
            // overflows, like a stack, rather than truncating a control.
            max(proposed, minimumWidth(of: subviews))
        } else {
            idealWidth(of: subviews)
        }
        let heights = zip(subviews, partWidths(in: width, subviews: subviews)).map { subview, partWidth in
            subview.sizeThatFits(ProposedViewSize(width: partWidth, height: nil)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let filter = index(of: .filter, in: subviews)
        var x = bounds.minX
        for (position, partWidth) in partWidths(in: bounds.width, subviews: subviews).enumerated() {
            if position == filter {
                x = bounds.maxX - partWidth // the filter sits at the trailing edge
            }
            subviews[position].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                                     proposal: ProposedViewSize(width: partWidth, height: nil))
            x += partWidth + spacing
        }
    }
}

extension QueueHeaderLayout {
    /// A part's role, set by `queueHeaderRole(_:)`; a part without one is rigid.
    struct RoleKey: LayoutValueKey {
        static let defaultValue = Role.rigid
    }

    /// Each part's width in a row `width` wide, by the policy above.
    private func partWidths(in width: CGFloat, subviews: Subviews) -> [CGFloat] {
        var widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let count = index(of: .count, in: subviews)
        let filter = index(of: .filter, in: subviews)
        let room = width - gaps(subviews) - rigidWidth(widths, count: count, filter: filter)
        let filterRange = filter.map { index in
            let minimum = minimumWidth(of: subviews[index])
            return minimum ... max(widths[index], minimum)
        }
        if let count {
            // The filter compresses first: while it can shrink to make room, the count is whole.
            // Past that the count gives way to the room the filter's minimum leaves, and keeps only
            // what its form needs of it — the compact form is narrower than the room.
            let filterMinimum = filterRange?.lowerBound ?? 0
            let offer: ProposedViewSize = room - widths[count] >= filterMinimum
                ? .unspecified
                : ProposedViewSize(width: max(room - filterMinimum, 0), height: nil)
            widths[count] = subviews[count].sizeThatFits(offer).width
        }
        if let filter, let filterRange {
            // The filter takes the rest, between its minimum and its ideal width.
            let rest = room - (count.map { widths[$0] } ?? 0)
            widths[filter] = min(max(rest, filterRange.lowerBound), filterRange.upperBound)
        }
        return widths
    }

    /// The row at its ideal width: every part at its ideal, the count whole.
    private func idealWidth(of subviews: Subviews) -> CGFloat {
        subviews.reduce(gaps(subviews)) { $0 + $1.sizeThatFits(.unspecified).width }
    }

    /// The narrowest the row gets without overflowing: the rigid parts and the filter's minimum.
    private func minimumWidth(of subviews: Subviews) -> CGFloat {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let count = index(of: .count, in: subviews)
        let filter = index(of: .filter, in: subviews)
        let filterMinimum = filter.map { minimumWidth(of: subviews[$0]) } ?? 0
        return gaps(subviews) + rigidWidth(widths, count: count, filter: filter) + filterMinimum
    }

    private func minimumWidth(of subview: LayoutSubview) -> CGFloat {
        subview.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
    }

    private func rigidWidth(_ widths: [CGFloat], count: Int?, filter: Int?) -> CGFloat {
        widths.indices.reduce(0) { total, index in
            index == count || index == filter ? total : total + widths[index]
        }
    }

    private func gaps(_ subviews: Subviews) -> CGFloat {
        spacing * CGFloat(max(subviews.count - 1, 0))
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
