import DesignTokenKit
import SwiftUI

// MARK: - Monitor Channel Column

/// The Monitoring tab's channels (S10.8 G1): one row per channel, `rowHeight` each, `MonitorLayout.rowGap`
/// apart, on `MonitorLensStack`'s lenses. Its own view so the band arrays are read HERE: the 20 Hz poll
/// re-evaluates this column, not the screen around it (its header, its height reader).
struct MonitorChannelColumn: View {
    let monitorVM: MonitoringViewModel
    let isPlaying: Bool
    let reduceMotion: Bool
    /// Each lens's height (`MonitorLayout.rowHeight`): an equal share of the tab's, or the least.
    let rowHeight: Double

    var body: some View {
        let total = monitorVM.channelCount
        VStack(spacing: CGFloat(MonitorLayout.rowGap)) {
            ForEach(0 ..< total, id: \.self) { channelIndex in
                let before = bandArray(monitorVM.beforeBands, channel: channelIndex)
                let after = bandArray(monitorVM.afterBands, channel: channelIndex)

                MonitorChannelRowView(
                    channelLabel: ChannelLabels.label(for: channelIndex, total: total),
                    spokenName: ChannelLabels.spokenName(for: channelIndex, total: total),
                    beforeBands: before,
                    afterBands: after,
                    isActive: isPlaying
                )
                .frame(height: CGFloat(rowHeight))
                // Only animate when reduce-motion is off; skip on first appearance.
                .animation(reduceMotion ? nil : .easeOut(duration: 0.06), value: before)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.06), value: after)
            }
        }
        // Every lens in one layer under every row (`MonitorLensStack`): no lens's shadow on another's bars.
        .background {
            MonitorLensStack(count: total, rowHeight: rowHeight)
        }
    }

    private func bandArray(_ arrays: [[Float]], channel: Int) -> [Float] {
        guard channel < arrays.count else {
            return [Float](repeating: 0, count: SpectrumConstants.bandCount)
        }
        return arrays[channel]
    }
}
