import DesignTokenKit
import EQEditKit
import SwiftUI

// MARK: - EQ graph analyzer silhouette (Sprint EQ, EQ3 — the analyzer lens, Sprint D grammar)

/// The music's shape behind the EQ curve: the analyzer's live bars as one soft silhouette in the
/// analyzer's own teal → lime ramp (`EQGraphDecor.silhouette`), each bar at its TRUE frequency on the
/// EQ's axis (`SpectrumConstants.barCentreHz`) — the analyser's bands tile 20 Hz – 20 kHz, the
/// graph's own axis, so the shape spans it, never stretched. Its own layer on the live clock
/// (`LiveTimeline`, each frame as it comes), so its redraw never repaints the curve, and it draws only
/// while a song plays and the window shows. Decorative: hit-transparent and hidden from VoiceOver.
struct EQGraphSilhouette: View {
    @Environment(AudioViewModel.self) private var audio

    /// Light smoothing passes over the bars, so the silhouette reads as a shape, not a bar field.
    private static let smoothingPasses = 3

    var body: some View {
        let sampler = audio.spectrum
        LiveTimeline(.frames, running: audio.isPlaying) { date in
            silhouette(Self.smoothed(sampler.bars(at: date)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func silhouette(_ bars: [Float]) -> some View {
        Canvas { context, size in
            let map = EQPlotMap.eqGraph(in: size)
            guard bars.count > 1, map.width > 0, map.height > 0 else { return }
            let reach = map.height * CGFloat(EQGraphDecor.silhouetteHeight)
            let firstX = map.x(forFreq: Double(SpectrumConstants.barCentreHz(0, of: bars.count)))
            let lastX = map.x(forFreq: Double(SpectrumConstants.barCentreHz(bars.count - 1, of: bars.count)))
            var path = Path()
            path.move(to: CGPoint(x: firstX, y: map.bottom))
            for (bar, value) in bars.enumerated() {
                let hz = Double(SpectrumConstants.barCentreHz(bar, of: bars.count))
                path.addLine(to: CGPoint(x: map.x(forFreq: hz), y: map.bottom - CGFloat(value) * reach))
            }
            path.addLine(to: CGPoint(x: lastX, y: map.bottom))
            path.closeSubpath()
            let stops = SpectrumRamp.stops.map { stop in
                Gradient.Stop(color: DesignSystem.Color.from(EQGraphDecor.silhouette(at: stop.position)),
                              location: CGFloat(stop.position))
            }
            context.fill(path, with: .linearGradient(Gradient(stops: stops),
                                                     startPoint: CGPoint(x: firstX, y: 0),
                                                     endPoint: CGPoint(x: lastX, y: 0)))
        }
    }

    /// The bars in 0…1, averaged over their neighbours a few times.
    private static func smoothed(_ bars: [Float]) -> [Float] {
        var values = bars.map { min(max($0, 0), 1) }
        guard values.count > 2 else { return values }
        for _ in 0 ..< smoothingPasses {
            values = values.indices.map { index in
                let window = values[max(0, index - 1) ... min(values.count - 1, index + 1)]
                return window.reduce(0, +) / Float(window.count)
            }
        }
        return values
    }
}
