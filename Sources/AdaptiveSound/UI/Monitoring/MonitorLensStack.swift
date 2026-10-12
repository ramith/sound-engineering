import DesignTokenKit
import SwiftUI

// MARK: - Monitor Lens Stack

/// The Monitoring tab's lenses (S10.8 G1): one analyzer lens per channel — the `.lens` glass the Now
/// Playing analyzer and the EQ graph wear, its bleed included — stacked as the channel rows are
/// (`MonitorLayout`), and drawn as ONE layer under every row's content (`MonitorChannelRowView`).
///
/// Why not a lens per row: a lens's drop shadow reaches up over the lens above it, and drawn with its own
/// row it painted over that lens's bars. In dark with Reduce Transparency or Increase Contrast — where the
/// opaque fill casts the shadow at full strength — the bars' foot came out 22% darker on every lens but
/// the last (4.8:1 → 3.3:1, measured on the picture sheets). In this layer the shadows only ever meet
/// glass, which they darken under the bars: the bars themselves stay as audited (R4-MON-01b).
struct MonitorLensStack: View {
    let count: Int
    /// Each lens's height: the channel rows' (`MonitorLayout.rowHeight`).
    let rowHeight: Double

    var body: some View {
        VStack(spacing: CGFloat(MonitorLayout.rowGap)) {
            ForEach(0 ..< count, id: \.self) { _ in
                Color.clear
                    .frame(height: CGFloat(rowHeight))
                    .glassPanel(.lens, in: RoundedRectangle(cornerRadius: CGFloat(GlassDecor.lensRadius),
                                                            style: .continuous))
            }
        }
    }
}
