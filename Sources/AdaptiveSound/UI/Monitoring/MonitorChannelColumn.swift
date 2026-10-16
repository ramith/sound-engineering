import DesignTokenKit
import SwiftUI

// MARK: - Monitor Channel Column

/// The Monitoring tab's channels (S10.8 G1): one row per channel, `rowHeight` each, `MonitorLayout.rowGap`
/// apart, on `MonitorLensStack`'s lenses — for one live-clock instant's `frame` of bands.
struct MonitorChannelColumn: View {
    let frame: MonitorFrame
    let isPlaying: Bool
    /// Each lens's height (`MonitorLayout.rowHeight`): an equal share of the tab's, or the least.
    let rowHeight: Double

    var body: some View {
        let total = frame.channelCount
        VStack(spacing: CGFloat(MonitorLayout.rowGap)) {
            ForEach(0 ..< total, id: \.self) { channelIndex in
                MonitorChannelRowView(
                    channelLabel: ChannelLabels.label(for: channelIndex, total: total),
                    spokenName: ChannelLabels.spokenName(for: channelIndex, total: total),
                    beforeBands: frame.before[channelIndex],
                    afterBands: frame.after[channelIndex],
                    isActive: isPlaying
                )
                .frame(height: CGFloat(rowHeight))
            }
        }
        // Every lens in one layer under every row (`MonitorLensStack`): no lens's shadow on another's bars.
        .background {
            MonitorLensStack(count: total, rowHeight: rowHeight)
        }
    }
}
