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
/// **Live only while it shows and plays** (council C-52): the lenses draw on the live clock
/// (`LiveTimeline`, each frame as it comes), reading `SpectrumSampler` — the one sampler every live
/// view shares — so nothing polls the engine for this tab while another tab is selected, the window
/// is closed or hidden, or the song is paused. Its per-channel analysers run only while it shows
/// (`showMonitoring`).
struct MonitoringTabView: View {
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        MonitoringTabContent(sampler: viewModel.spectrum, isPlaying: viewModel.isPlaying)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // No background: the app glow shows through (`TabContentView`, S10.8 F1).
            .onAppear { viewModel.spectrum.showMonitoring(true) }
            .onDisappear { viewModel.spectrum.showMonitoring(false) }
    }
}

// MARK: - Monitoring Tab Content

/// The header over one lens per channel. The lenses — and the "waiting" state before the engine has
/// channels — sit on the live clock; the header around them doesn't redraw with it.
private struct MonitoringTabContent: View {
    let sampler: SpectrumSampler
    let isPlaying: Bool

    var body: some View {
        // The region's height sets each lens's (`MonitorLayout`, S10.8 G1): with few channels the lenses
        // divide what the header leaves; past `rowMinHeight` each keeps that and the column scrolls. The
        // scroll view spans the whole content region and the lenses sit inside its insets, so its clip —
        // the region's own edge, which the shell clips anyway — never cuts a lens's shadow at rest, and a
        // scrolled-away lens never draws (or takes clicks) over the chrome: no `.scrollClipDisabled()`, as
        // Settings.
        GeometryReader { proxy in
            let regionHeight = Double(proxy.size.height)
            // edgeToEdge: the column brings its own (Twin Panels) insets rather than Screen's.
            Screen(edgeToEdge: true) {
                VStack(spacing: CGFloat(MonitorLayout.headerGap)) {
                    MonitoringHeaderView()
                        .frame(height: CGFloat(MonitorLayout.headerHeight), alignment: .top)

                    LiveTimeline(.frames, running: isPlaying) { date in
                        let frame = sampler.monitorFrame(at: date)
                        if frame.channelCount == 0 {
                            MonitoringEmptyView()
                                .frame(height: CGFloat(MonitorLayout.rowsHeight(regionHeight: regionHeight)))
                        } else {
                            MonitorChannelColumn(
                                frame: frame,
                                isPlaying: isPlaying,
                                rowHeight: MonitorLayout.rowHeight(channelCount: frame.channelCount,
                                                                   regionHeight: regionHeight)
                            )
                        }
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
