import SwiftUI

// MARK: - FrequencyResponseCanvas drawing + curve math (kept out of the main file so the

// SwiftUI view's own body stays under SwiftLint `type_body_length`).

/// The plot's pixel-space rectangle, resolved once per `Canvas` redraw and threaded through
/// the drawing helpers below. Grouping the four margins into one value (plus derived `width`/
/// `height`) keeps each helper under the parameter-count ceiling without losing the
/// descriptive per-edge names at call sites.
struct PlotGeometry {
    let left: CGFloat
    let right: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    var width: CGFloat {
        right - left
    }

    var height: CGFloat {
        bottom - top
    }
}

extension FrequencyResponseCanvas {
    // MARK: - Drawing Helpers

    func drawGridAndLabels(context: inout GraphicsContext, geometry: PlotGeometry) {
        let dbLevels = [-20.0, -10.0, 0.0, 10.0, 20.0]
        for dbLevel in dbLevels {
            let yPos = geometry.bottom - ((dbLevel + 20.0) / 40.0) * geometry.height

            var gridLine = Path()
            gridLine.move(to: CGPoint(x: geometry.left, y: yPos))
            gridLine.addLine(to: CGPoint(x: geometry.right, y: yPos))

            let strokeColor = dbLevel == 0.0 ? Color.asAccent.opacity(0.3) : Color.asHairline
            let lineWidth: CGFloat = dbLevel == 0.0 ? 1 : 0.5
            context.stroke(gridLine, with: .color(strokeColor), lineWidth: lineWidth)

            let labelText = Text("\(Int(dbLevel))").font(.caption)
            let resolvedLabel = context.resolve(labelText)
            context.draw(resolvedLabel, at: CGPoint(x: geometry.left - 15, y: yPos), anchor: .trailing)
        }

        let freqLabels = [(20, "20Hz"), (200, "200Hz"), (2000, "2kHz"), (20000, "20kHz")]
        for (freq, freqLabel) in freqLabels {
            let logFreq = log10(Double(freq))
            let xPos = geometry.left
                + (logFreq - log10(20.0)) / (log10(20000.0) - log10(20.0)) * geometry.width

            var gridLine = Path()
            gridLine.move(to: CGPoint(x: xPos, y: geometry.top))
            gridLine.addLine(to: CGPoint(x: xPos, y: geometry.bottom))
            context.stroke(gridLine, with: .color(Color.asHairline), lineWidth: 0.5)

            let labelText = Text(freqLabel).font(.caption)
            let resolvedLabel = context.resolve(labelText)
            context.draw(resolvedLabel, at: CGPoint(x: xPos, y: geometry.bottom + 12), anchor: .top)
        }
    }

    func drawFrequencyResponseCurve(
        context: inout GraphicsContext,
        eqValues: [(freq: Double, gain: Double)],
        geometry: PlotGeometry
    ) {
        let interpolatedPoints = interpolateFrequencyResponse(eqValues)

        var curvePath = Path()
        var isFirstPoint = true

        for (freq, gain) in interpolatedPoints {
            let logFreq = log10(freq)
            let xPos = geometry.left
                + (logFreq - log10(20.0)) / (log10(20000.0) - log10(20.0)) * geometry.width
            let yPos = geometry.bottom - ((gain + 20.0) / 40.0) * geometry.height

            if isFirstPoint {
                curvePath.move(to: CGPoint(x: xPos, y: yPos))
                isFirstPoint = false
            } else {
                curvePath.addLine(to: CGPoint(x: xPos, y: yPos))
            }
        }

        context.stroke(curvePath, with: .color(Color.asAccent), lineWidth: 2.5)
    }

    func drawISOOctaveDots(
        context: inout GraphicsContext,
        eqValues: [(freq: Double, gain: Double)],
        geometry: PlotGeometry
    ) {
        let dotRadius: CGFloat = 4.0

        for (freq, gain) in eqValues {
            let logFreq = log10(freq)
            let xPos = geometry.left
                + (logFreq - log10(20.0)) / (log10(20000.0) - log10(20.0)) * geometry.width
            let yPos = geometry.bottom - ((gain + 20.0) / 40.0) * geometry.height

            let dotPath = Path(ellipseIn: CGRect(
                x: xPos - dotRadius,
                y: yPos - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
            context.fill(dotPath, with: .color(Color.asAccent))
        }
    }

    /// Highlight the keyboard-targeted band (A-H1): a full-height guide plus a ring around its dot,
    /// using the same log-frequency-x / linear-gain-y mapping as `drawISOOctaveDots`.
    func drawKeyboardCursor(context: inout GraphicsContext, geometry: PlotGeometry, bandIndex: Int) {
        guard EQPreset.isoFrequencies.indices.contains(bandIndex) else { return }
        let freq = EQPreset.isoFrequencies[bandIndex]
        let gain = Double(eqViewModel.bandGains[bandIndex])
        let xPos = geometry.left
            + (log10(freq) - log10(20.0)) / (log10(20000.0) - log10(20.0)) * geometry.width
        let yPos = geometry.bottom - ((gain + 20.0) / 40.0) * geometry.height

        var guide = Path()
        guide.move(to: CGPoint(x: xPos, y: geometry.top))
        guide.addLine(to: CGPoint(x: xPos, y: geometry.bottom))
        context.stroke(guide, with: .color(Color.asAccent.opacity(0.4)), lineWidth: 1)

        let ringRadius: CGFloat = 7
        let ring = Path(ellipseIn: CGRect(
            x: xPos - ringRadius, y: yPos - ringRadius,
            width: ringRadius * 2, height: ringRadius * 2
        ))
        context.stroke(ring, with: .color(Color.asAccent), lineWidth: 2)
    }

    // MARK: - Interpolation & Smoothing

    private func interpolateFrequencyResponse(
        _ isoPoints: [(freq: Double, gain: Double)]
    ) -> [(freq: Double, gain: Double)] {
        guard !isoPoints.isEmpty else { return isoPoints }

        var interpolatedFreqs: [Double] = []
        let logFreqMin = log10(20.0)
        let logFreqMax = log10(20000.0)
        let numSteps = 120

        for step in 0 ... numSteps {
            let ratio = Double(step) / Double(numSteps)
            let logFreq = logFreqMin + ratio * (logFreqMax - logFreqMin)
            interpolatedFreqs.append(pow(10.0, logFreq))
        }

        var interpolatedGains: [Double] = interpolatedFreqs.map { freq in
            gainAtFrequency(freq, from: isoPoints)
        }

        interpolatedGains = smoothGains(interpolatedGains, tapCount: 3)

        return zip(interpolatedFreqs, interpolatedGains).map { ($0, $1) }
    }

    private func gainAtFrequency(
        _ freq: Double,
        from isoPoints: [(freq: Double, gain: Double)]
    ) -> Double {
        guard freq >= 20 && freq <= 20000 else { return 0 }

        let logFreq = log10(freq)
        var lower = isoPoints[0]
        var upper = isoPoints.last ?? isoPoints[0]

        for idx in 0 ..< (isoPoints.count - 1) {
            if logFreq >= log10(isoPoints[idx].freq) && logFreq <= log10(isoPoints[idx + 1].freq) {
                lower = isoPoints[idx]
                upper = isoPoints[idx + 1]
                break
            }
        }

        let logLower = log10(lower.freq)
        let logUpper = log10(upper.freq)
        let position = (logFreq - logLower) / (logUpper - logLower)
        let clamped = max(0, min(1, position))

        return lower.gain + clamped * (upper.gain - lower.gain)
    }

    private func smoothGains(_ gains: [Double], tapCount: Int) -> [Double] {
        guard gains.count >= tapCount else { return gains }

        let halfTap = tapCount / 2
        var smoothed = gains

        // Preserve the first and last samples (freq 20 Hz / 20 kHz) so the drawn curve reaches the
        // boundary control dots EXACTLY. A moving average over a shrinking boundary window pulls the
        // endpoint toward its inner neighbour, which left a sharp edge band (e.g. a 20 kHz cut or
        // boost) with the curve visibly short of its dot — most obvious once the keyboard cursor
        // ring sits precisely on that dot. Interior points still smooth as before.
        for idx in 1 ..< (gains.count - 1) {
            var sum = 0.0
            var count = 0

            for tap in max(0, idx - halfTap) ... min(gains.count - 1, idx + halfTap) {
                sum += gains[tap]
                count += 1
            }

            smoothed[idx] = sum / Double(count)
        }

        return smoothed
    }
}
