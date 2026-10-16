import DesignTokenKit
import SwiftUI

// MARK: - Spectrum Analyzer View

/// Real-time FFT bars + peak-hold caps inside the Regime-B LENS, with the 8a instrument
/// dressing (PR 5, now that the D6 frame exists): a "0 dB" reference label ABOVE the bar
/// field, four horizontal gridline hairlines behind the bars, and the 20 Hz–20 kHz axis strip
/// BELOW it. Labels never overlay the bars (§7 R4 pair 9: the palette's near-white lime would
/// sink small text — the strips resolve it by placement, not a scrim).
///
/// The bar field is ONE `Canvas` on the live clock (council C-52, UI-2): while a song plays and the
/// window shows, it asks `SpectrumSampler` for the bars and caps at each instant and draws all 88 in
/// one pass — the look of the 88 animated views it replaces, at a fraction of the cost (each view
/// re-diffed and animated per frame). Paused, it draws once and stops; the caps freeze. The bar
/// FIELD stays hidden from accessibility (decorative); the LENS ELEMENT itself is exposed by HeroRow.
struct SpectrumAnalyzerView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// Bar geometry: as the shipped `HStack(spacing: 2)` of `RoundedRectangle(cornerRadius: 2)`s.
    private enum BarMetrics {
        static let spacing: CGFloat = 2
        static let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
    }

    /// Cap geometry; its opacity is per appearance (`spectrumCapOpacity`). A full-scale cap stands
    /// `overhang` above the bar field, as the shipped caps did: the field's `Canvas` reaches that far up.
    private enum CapMetrics {
        static let height: CGFloat = 2
        static let gapAboveBar: CGFloat = 4
        static let overhang = height + gapAboveBar
        static let shape = RoundedRectangle(cornerRadius: 1, style: .continuous)
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
        let isPlaying = viewModel.isPlaying
        let isPure = viewModel.signalPath.path == .pure
        let sampler = viewModel.spectrum
        let reduceMotion = reduceMotion
        return LiveTimeline(.motion, running: isPlaying) { date in
            let frame = sampler.lens(at: date, isPlaying: isPlaying, isPure: isPure, reduceMotion: reduceMotion)
            Canvas { context, size in
                Self.draw(frame, in: &context, size: size)
            }
            .padding(.top, -CapMetrics.overhang) // the caps' headroom above the field
        }
        .background { gridlines }
        .opacity(isPlaying ? 1.0 : 0.4)
    }

    /// The 88 bars, and each cap that stands clear of its bar, laid out as the shipped `HStack` laid
    /// them out: equal widths, 2 pt apart, bottom-aligned, every edge on the pixel grid as SwiftUI
    /// placed each bar's and cap's view; each filled with its own vertical gradient. `size` includes
    /// the caps' overhang above the field.
    private static func draw(_ frame: SpectrumLensFrame, in context: inout GraphicsContext, size: CGSize) {
        let count = frame.bars.count
        let field = size.height - CapMetrics.overhang
        guard count > 0, size.width > 0, field > 0 else { return }
        let scale = max(context.environment.displayScale, 1)
        let snapped = { (value: CGFloat) in (value * scale).rounded() / scale }
        let width = (size.width - BarMetrics.spacing * CGFloat(count - 1)) / CGFloat(count)
        let gradients = SpectrumColorPalette.barGradients(count: count, in: context.environment)
        var caps = context
        caps.opacity = context.spectrumCapOpacity
        let bottom = snapped(size.height)
        for index in 0 ..< count {
            let left = CGFloat(index) * (width + BarMetrics.spacing)
            let column = snapped(left) ... snapped(left + width)
            let barHeight = CGFloat(min(max(frame.bars[index], 0), 1)) * field
            if barHeight > 0 {
                let top = snapped(size.height - barHeight)
                let bar = CGRect(x: column.lowerBound, y: top, width: column.upperBound - column.lowerBound,
                                 height: bottom - top)
                context.fill(BarMetrics.shape.path(in: bar), with: verticalFill(gradients[index], over: bar))
            }
            let capHeight = index < frame.caps.count ? CGFloat(min(max(frame.caps[index], 0), 1)) * field : 0
            if capHeight > barHeight + 1 {
                let top = snapped(size.height - CapMetrics.height - capHeight - CapMetrics.gapAboveBar)
                let cap = CGRect(x: column.lowerBound, y: top, width: column.upperBound - column.lowerBound,
                                 height: CapMetrics.height)
                caps.fill(CapMetrics.shape.path(in: cap), with: verticalFill(gradients[index], over: cap))
            }
        }
    }

    /// `gradient` from the top of `rect` to its bottom: a `LinearGradient(.top → .bottom)` on that shape.
    private static func verticalFill(_ gradient: Gradient, over rect: CGRect) -> GraphicsContext.Shading {
        .linearGradient(gradient, startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY))
    }

    /// Four horizontal hairlines (8a: white 4–6% — the glass hairline token) behind the bars.
    private var gridlines: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< AxisMetrics.gridlineCount, id: \.self) { _ in
                Rectangle()
                    .fill(Color.asHairline)
                    .frame(height: 0.5)
                Spacer(minLength: 0)
            }
        }
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
