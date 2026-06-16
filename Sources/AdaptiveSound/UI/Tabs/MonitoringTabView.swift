import SwiftUI

// MARK: - Monitoring Tab View

/// Dedicated signal-monitoring tab (Sprint 5 M3/M4).
///
/// v1 layout: one full-width row per channel (N-channel aware — 1 row mono,
/// 2 rows stereo, up to 8 rows for 7.1). Each row shows the per-channel BEFORE
/// (pre-DSP, teal) vs AFTER (post-DSP, blue) spectrum side by side.
///
/// **Tab-visibility-gated polling**: an async Task starts when this view appears
/// and is cancelled when it disappears; `MonitoringViewModel` does the actual
/// timer loop. The engine is never polled on behalf of this tab while another
/// tab is selected.
struct MonitoringTabView: View {
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Created once and retained for the lifetime of the tab.
    @State private var monitorVM: MonitoringViewModel?

    var body: some View {
        Group {
            if let monitorVM {
                MonitoringTabContent(
                    monitorVM: monitorVM,
                    isPlaying: viewModel.isPlaying,
                    reduceMotion: reduceMotion
                )
            } else {
                // Shown only during the brief window before the first .task fires.
                MonitoringEmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Color.window)
        .task {
            // Create once — .task is cancelled/re-run if the view leaves and re-enters
            // the hierarchy (tab switch), so this also handles stopping + restarting.
            let monVM = MonitoringViewModel(engine: viewModel.engine)
            monitorVM = monVM
            monVM.startPolling()
            // Suspend here until the task is cancelled (tab leaves).
            await withTaskCancellationHandler {
                try? await Task.sleep(for: .seconds(86400)) // sleeps until cancelled
            } onCancel: {
                Task { @MainActor in monVM.stopPolling() }
            }
        }
    }
}

// MARK: - Monitoring Tab Content

/// The populated content once MonitoringViewModel is ready.
/// Extracted to keep MonitoringTabView's body below the function-body length limit.
private struct MonitoringTabContent: View {
    let monitorVM: MonitoringViewModel
    let isPlaying: Bool
    let reduceMotion: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: DesignSystem.Spacing.small) {
                MonitoringHeaderView()

                if monitorVM.channelCount == 0 {
                    MonitoringEmptyView()
                } else {
                    channelRows
                }
            }
            .padding(DesignSystem.Spacing.medium)
        }
    }

    private var channelRows: some View {
        ForEach(0 ..< monitorVM.channelCount, id: \.self) { channelIndex in
            let label = ChannelLabels.label(for: channelIndex, total: monitorVM.channelCount)
            let before = bandArray(monitorVM.beforeBands, channel: channelIndex)
            let after = bandArray(monitorVM.afterBands, channel: channelIndex)

            MonitorChannelRowView(
                channelIndex: channelIndex,
                channelLabel: label,
                beforeBands: before,
                afterBands: after,
                isActive: isPlaying
            )
            // Only animate when reduce-motion is off; skip on first appearance.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.06), value: before)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.06), value: after)
        }
    }

    private func bandArray(_ arrays: [[Float]], channel: Int) -> [Float] {
        guard channel < arrays.count else {
            return [Float](repeating: 0, count: SpectrumConstants.bandCount)
        }
        return arrays[channel]
    }
}

// MARK: - Monitoring Header View

/// Section header displayed above the channel rows.
private struct MonitoringHeaderView: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                Text("Signal Monitor")
                    .font(DesignSystem.Font.sectionTitle)
                    .foregroundStyle(DesignSystem.Color.label)

                Text("Per-channel before/after DSP spectrum")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
            }

            Spacer()

            LegendView()
        }
        .padding(.bottom, DesignSystem.Spacing.xSmall)
    }
}

// MARK: - Legend View

/// Small colour legend: BEFORE (teal) / AFTER (blue).
private struct LegendView: View {
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            legendItem(color: DesignSystem.Color.accent, label: "Before")
            legendItem(color: DesignSystem.Color.blue, label: "After")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xSmall) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 4)

            Text(label)
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) spectrum colour")
    }
}

// MARK: - Monitoring Empty View

/// Shown while the engine is not yet ready (channelCount == 0).
private struct MonitoringEmptyView: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            Spacer()

            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .accessibilityHidden(true)

            Text("Waiting for audio engine…")
                .font(DesignSystem.Font.body)
                .foregroundStyle(DesignSystem.Color.labelSecondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Monitoring unavailable — audio engine not ready")
    }
}

// MARK: - Channel Labels

/// Maps a 0-based channel index to a human-readable label.
///
/// Follows the conventional channel ordering used by AVAudioChannelLayout / ITU-R BS.775:
///   0=L, 1=R, 2=C, 3=LFE, 4=Ls, 5=Rs, 6=Lss, 7=Rss
enum ChannelLabels {
    private static let mono = ["M"]
    private static let stereo = ["L", "R"]
    private static let surround51 = ["L", "R", "C", "LFE", "Ls", "Rs"]
    private static let surround71 = ["L", "R", "C", "LFE", "Ls", "Rs", "Lss", "Rss"]

    static func label(for index: Int, total: Int) -> String {
        let table: [String]
        switch total {
        case 1: table = mono
        case 2: table = stereo
        case 6: table = surround51
        case 8: table = surround71
        default:
            // Fallback for non-standard layouts: "Ch 1", "Ch 2", …
            return "Ch \(index + 1)"
        }
        guard index < table.count else { return "Ch \(index + 1)" }
        return table[index]
    }
}
