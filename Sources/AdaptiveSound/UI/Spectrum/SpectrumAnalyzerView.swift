import SwiftUI

// MARK: - Spectrum Analyzer View

/// Displays real-time FFT magnitude bars sourced from `AudioViewModel.spectrumBars`.
///
/// The ViewModel updates `spectrumBars` on the main thread at ~20 Hz via a Timer.
/// SwiftUI's `@Observable` machinery propagates changes to this view automatically;
/// no `TimelineView` or fake random data is needed.
///
/// Accessibility: the view is hidden from the accessibility tree (it is a purely
/// decorative animation). Screen readers will still see the playback controls.
struct SpectrumAnalyzerView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        let bars = viewModel.spectrumBars
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0 ..< bars.count, id: \.self) { index in
                // Compute normalized horizontal position: 0 (left/low-freq) to 1 (right/high-freq)
                let t = bars.count > 1 ? Float(index) / Float(bars.count - 1) : 0

                // Get the frequency-based gradient for this bar
                let barGradient = SpectrumColorPalette.gradientAt(t)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barGradient)
                    // Height is in [0, 1]; clamp defensively before scaling to 50pt.
                    .frame(height: CGFloat(min(max(bars[index], 0), 1)) * 50)
                    // Animate height changes with a short ease-out.
                    // When reduceMotion is on, skip the animation entirely.
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.08),
                        value: bars[index]
                    )
            }
        }
        .opacity(viewModel.isPlaying ? 1.0 : 0.4)
        .accessibilityHidden(true)
    }
}
