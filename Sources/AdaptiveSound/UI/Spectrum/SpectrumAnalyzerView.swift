import DesignTokenKit
import SwiftUI

// MARK: - Spectrum Analyzer View

/// Real-time FFT bars + peak-hold caps inside the Regime-B LENS, with the 8a instrument
/// dressing (PR 5, now that the D6 frame exists): a "0 dB" reference label ABOVE the bar
/// field, four horizontal gridline hairlines behind the bars, and the 20 Hz–20 kHz axis strip
/// BELOW it. Labels never overlay the bars (§7 R4 pair 9: the palette's near-white lime would
/// sink small text — the strips resolve it by placement, not a scrim).
///
/// Bars + caps update from the same 20 Hz main-thread tick (one `@Observable` invalidation);
/// caps freeze on pause structurally (the tracker is time-fed). The bar FIELD stays hidden
/// from accessibility (decorative animation); the LENS ELEMENT itself is exposed by HeroRow.
struct SpectrumAnalyzerView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private enum CapMetrics {
        static let height: CGFloat = 2
        static let gapAboveBar: CGFloat = 4
        static let opacity: Double = 0.5
    }

    /// Decorative axis text (a11y-hidden; sub-10pt is allowed for decorative-only, §3.2).
    private enum AxisMetrics {
        static let font = SwiftUI.Font.system(size: 9, design: .monospaced)
        static let gridlineCount = 4
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Spacer()
                Text("0 dB")
                    .font(AxisMetrics.font)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
            }
            barField
            axisStrip
        }
        .padding(DesignSystem.Spacing.small)
        .glassPanel(.lens, in: RoundedRectangle(cornerRadius: CGFloat(GlassDecor.lensRadius),
                                                style: .continuous))
        .accessibilityHidden(true) // HeroRow exposes the lens element + its action
    }

    // MARK: Bar field (bars + caps over the gridlines)

    private var barField: some View {
        let bars = viewModel.spectrumBars
        let caps = viewModel.peakCaps
        return GeometryReader { geo in
            let maxBarHeight = geo.size.height
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0 ..< bars.count, id: \.self) { index in
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
            .background { gridlines(in: geo.size) }
        }
        .opacity(viewModel.isPlaying ? 1.0 : 0.4)
    }

    /// Four horizontal hairlines (8a: white 4–6% — the glass hairline token) behind the bars.
    private func gridlines(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            ForEach(0 ..< AxisMetrics.gridlineCount, id: \.self) { _ in
                Rectangle()
                    .fill(Color.asHairline)
                    .frame(height: 0.5)
                Spacer(minLength: 0)
            }
        }
        .frame(height: size.height)
    }

    // MARK: Axis strip (20 Hz – 20 kHz, decorative)

    private var axisStrip: some View {
        HStack {
            Text("20 Hz").font(AxisMetrics.font)
            Spacer()
            Text("200 Hz").font(AxisMetrics.font)
            Spacer()
            Text("2 kHz").font(AxisMetrics.font)
            Spacer()
            Text("20 kHz").font(AxisMetrics.font)
        }
        .foregroundStyle(DesignSystem.Color.labelTertiary)
    }
}
