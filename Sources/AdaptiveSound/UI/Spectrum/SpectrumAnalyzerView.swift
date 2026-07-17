import DesignTokenKit
import SwiftUI

// MARK: - Spectrum Analyzer View

/// Displays real-time FFT magnitude bars sourced from `AudioViewModel.spectrumBars`, with
/// peak-hold caps (`AudioViewModel.peakCaps` — S10.7 PR 3) riding 4pt above each bar, inside
/// the Regime-B analyzer LENS (`.glassPanel(.lens)`; the D6 hero-right frame + dB grid/axis
/// scale arrive with the PR-5 restructure — this styling is size-agnostic).
///
/// The ViewModel updates both arrays in the same main-thread tick at ~20 Hz; `@Observable`
/// coalesces them into one invalidation. Caps freeze on pause structurally (the tracker is
/// time-FED; paused ticks don't feed it).
///
/// Accessibility: the bar field is hidden from the accessibility tree (purely decorative
/// animation). Screen readers still see the playback controls.
struct SpectrumAnalyzerView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// Cap geometry (8a): 2pt cap, 4pt above the bar top, bar color at 50%.
    private enum CapMetrics {
        static let height: CGFloat = 2
        static let gapAboveBar: CGFloat = 4
        static let opacity: Double = 0.5
    }

    var body: some View {
        let bars = viewModel.spectrumBars
        let caps = viewModel.peakCaps
        GeometryReader { geo in
            let maxBarHeight = geo.size.height
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0 ..< bars.count, id: \.self) { index in
                    // Normalized horizontal position: 0 (low freq) → 1 (high freq).
                    let t = bars.count > 1 ? Float(index) / Float(bars.count - 1) : 0
                    let barGradient = SpectrumColorPalette.gradientAt(t)
                    let barHeight = CGFloat(min(max(bars[index], 0), 1)) * maxBarHeight
                    let capValue = index < caps.count ? CGFloat(min(max(caps[index], 0), 1)) : 0

                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(barGradient)
                            .frame(height: barHeight)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.08),
                                       value: bars[index])

                        // The peak-hold cap: only once it separates from the bar top (a cap
                        // riding the live bar is visual noise).
                        if capValue * maxBarHeight > barHeight + 1 {
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(barGradient)
                                .opacity(CapMetrics.opacity)
                                .frame(height: CapMetrics.height)
                                .offset(y: -(capValue * maxBarHeight + CapMetrics.gapAboveBar))
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.08),
                                           value: caps[index])
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .opacity(viewModel.isPlaying ? 1.0 : 0.4)
        .accessibilityHidden(true)
        .padding(DesignSystem.Spacing.small)
        .glassPanel(.lens, in: RoundedRectangle(cornerRadius: CGFloat(GlassDecor.lensRadius),
                                                style: .continuous))
    }
}
