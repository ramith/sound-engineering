import DesignTokenKit
import SwiftUI

// MARK: - Monitoring Tab View

/// Dedicated signal-monitoring tab.
///
/// One full-width analyzer lens per channel (N-channel aware — 1 lens mono,
/// 2 stereo, up to 8 for 7.1), sharing the tab's height and scrolling past what fits
/// (S10.8 G1, `MonitorLayout`). Each lens shows the channel's BEFORE (pre-DSP,
/// neutral grey) and AFTER (post-DSP, the analyzer's teal → lime) spectrum side by
/// side, each half under its own tag (decision 4).
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
        // No background: the app glow shows through (`TabContentView`, S10.8 F1).
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

/// The populated content once MonitoringViewModel is ready: the header over one lens per channel.
/// Extracted to keep MonitoringTabView's body below the function-body length limit. It reads only the
/// channel count; the bands are read by `MonitorChannelColumn`, so the poll redraws the lenses alone.
private struct MonitoringTabContent: View {
    let monitorVM: MonitoringViewModel
    let isPlaying: Bool
    let reduceMotion: Bool

    var body: some View {
        // The region's height sets each lens's (`MonitorLayout`, S10.8 G1): with few channels the lenses
        // divide what the header leaves; past `rowMinHeight` each keeps that and the column scrolls. The
        // `.task`/polling lifecycle lives on MonitoringTabView (unchanged), so this container doesn't
        // affect start/stop-on-tab-switch. The scroll view spans the whole content region and the
        // lenses sit inside its insets, so its clip — the region's own edge, which the shell clips
        // anyway — never cuts a lens's shadow at rest, and a scrolled-away lens never draws (or takes
        // clicks) over the chrome: no `.scrollClipDisabled()`, as Settings.
        GeometryReader { proxy in
            let regionHeight = Double(proxy.size.height)
            // edgeToEdge: the column brings its own (Twin Panels) insets rather than Screen's.
            Screen(edgeToEdge: true) {
                VStack(spacing: CGFloat(MonitorLayout.headerGap)) {
                    MonitoringHeaderView()
                        .frame(height: CGFloat(MonitorLayout.headerHeight), alignment: .top)

                    if monitorVM.channelCount == 0 {
                        MonitoringEmptyView()
                            .frame(height: CGFloat(MonitorLayout.rowsHeight(regionHeight: regionHeight)))
                    } else {
                        MonitorChannelColumn(
                            monitorVM: monitorVM,
                            isPlaying: isPlaying,
                            reduceMotion: reduceMotion,
                            rowHeight: MonitorLayout.rowHeight(channelCount: monitorVM.channelCount,
                                                               regionHeight: regionHeight)
                        )
                    }
                }
                .padding(.top, CGFloat(MonitorLayout.insetTop))
                .padding(.horizontal, CGFloat(MonitorLayout.insetHorizontal))
                .padding(.bottom, CGFloat(MonitorLayout.insetBottom))
            }
        }
    }
}

// MARK: - Monitoring Header View

/// Section header displayed above the channel lenses, framed to `MonitorLayout.headerHeight`
/// (LAY-MON-01f measures its two lines).
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
    }
}

// MARK: - Legend View

/// Small colour legend: BEFORE (neutral grey) / AFTER (the analyzer's teal → lime).
private struct LegendView: View {
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            legendItem(swatch: MonitorColors.beforeFill, label: "Before")
            legendItem(swatch: MonitorColors.afterSwatch, label: "After")
        }
    }

    private func legendItem(swatch: some ShapeStyle, label: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xSmall) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(swatch)
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
