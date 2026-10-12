import SwiftUI

// MARK: - Spectrum Mini View

/// A compact, `Canvas`-based spectrum visualiser for a single tap point + channel.
///
/// Designed to be embedded inside `MonitorChannelRowView` for the Monitoring tab.
/// The caller owns the band data array and passes it in; this view is pure drawing.
///
/// - `bands`: Normalised magnitudes in [0, 1], one element per FFT band.
/// - `barColors`: How the bars are coloured — BEFORE's grey or AFTER's analyzer ramp (decision 4).
/// - `isActive`: When `false` the view renders at reduced opacity (not playing).
struct SpectrumMiniView: View {
    /// How the bars are coloured (S10.8 F1, decision 4; `MonitorColors`).
    enum BarColors: Equatable {
        /// One colour for every bar: BEFORE's neutral grey.
        case uniform(Color)
        /// The analyzer's teal → lime, a flat colour per bar, low → high frequency: AFTER.
        case analyzerRamp
    }

    let bands: [Float]
    let barColors: BarColors
    let isActive: Bool

    // MARK: Constants

    private enum Layout {
        static let barSpacing: CGFloat = 1
        static let cornerRadius: CGFloat = 1.5
        static let minBarHeight: CGFloat = 1 // keep silent bars just barely visible
        static let inactiveOpacity: Double = 0.25
    }

    var body: some View {
        Canvas { context, size in
            drawBars(context: &context, size: size)
        }
        .opacity(isActive ? 1.0 : Layout.inactiveOpacity)
        // Pure decoration — screen readers get the per-row label instead.
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private func drawBars(context: inout GraphicsContext, size: CGSize) {
        let count = bands.count
        guard count > 0 else { return }

        let totalSpacing = Layout.barSpacing * CGFloat(count - 1)
        let barWidth = max(1, (size.width - totalSpacing) / CGFloat(count))
        let colors = switch barColors {
        case let .uniform(color): Array(repeating: color, count: count)
        case .analyzerRamp: MonitorColors.afterFills(count: count)
        }

        for index in 0 ..< count {
            let magnitude = CGFloat(min(max(bands[index], 0), 1))
            let barHeight = max(Layout.minBarHeight, magnitude * size.height)
            let xOrigin = CGFloat(index) * (barWidth + Layout.barSpacing)
            let yOrigin = size.height - barHeight

            let rect = CGRect(x: xOrigin, y: yOrigin, width: barWidth, height: barHeight)
            let barPath = Path(roundedRect: rect, cornerRadius: Layout.cornerRadius)
            context.fill(barPath, with: .color(colors[index]))
        }
    }
}
