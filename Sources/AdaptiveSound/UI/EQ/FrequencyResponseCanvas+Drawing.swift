import EQEditKit
import SwiftUI

// MARK: - FrequencyResponseCanvas drawing + curve math

//
// Kept out of the main file so the SwiftUI view's own body stays under SwiftLint `type_body_length`.
// Every position goes through the kit's `EQPlotMap`, the same map the drag hit-tests with.

extension FrequencyResponseCanvas {
    // MARK: - Drawing Helpers

    func drawGridAndLabels(context: inout GraphicsContext, map: EQPlotMap) {
        let dbLevels = [-20.0, -10.0, 0.0, 10.0, 20.0]
        for dbLevel in dbLevels {
            let yPos = map.y(forGain: dbLevel)

            var gridLine = Path()
            gridLine.move(to: CGPoint(x: map.left, y: yPos))
            gridLine.addLine(to: CGPoint(x: map.right, y: yPos))

            let strokeColor = dbLevel == 0.0 ? Color.asAccent.opacity(0.3) : Color.asHairline
            let lineWidth: CGFloat = dbLevel == 0.0 ? 1 : 0.5
            context.stroke(gridLine, with: .color(strokeColor), lineWidth: lineWidth)

            let labelText = Text("\(Int(dbLevel))").font(.caption)
            context.draw(context.resolve(labelText), at: CGPoint(x: map.left - 15, y: yPos), anchor: .trailing)
        }

        let freqLabels: [(freq: Double, label: String)] = [
            (20, "20Hz"), (200, "200Hz"), (2000, "2kHz"), (20000, "20kHz"),
        ]
        for (freq, freqLabel) in freqLabels {
            let xPos = map.x(forFreq: freq)

            var gridLine = Path()
            gridLine.move(to: CGPoint(x: xPos, y: map.top))
            gridLine.addLine(to: CGPoint(x: xPos, y: map.bottom))
            context.stroke(gridLine, with: .color(Color.asHairline), lineWidth: 0.5)

            let labelText = Text(freqLabel).font(.caption)
            context.draw(context.resolve(labelText), at: CGPoint(x: xPos, y: map.bottom + 12), anchor: .top)
        }
    }

    func drawFrequencyResponseCurve(
        context: inout GraphicsContext,
        eqValues: [(freq: Double, gain: Double)],
        map: EQPlotMap
    ) {
        let interpolatedPoints = interpolateFrequencyResponse(eqValues)

        var curvePath = Path()
        var isFirstPoint = true
        for (logFreq, gain) in interpolatedPoints {
            let point = CGPoint(x: map.x(forLogFreq: logFreq), y: map.y(forGain: gain))
            if isFirstPoint {
                curvePath.move(to: point)
                isFirstPoint = false
            } else {
                curvePath.addLine(to: point)
            }
        }

        context.stroke(curvePath, with: .color(Color.asAccent), lineWidth: 2.5)
    }

    func drawISOOctaveDots(
        context: inout GraphicsContext,
        eqValues: [(freq: Double, gain: Double)],
        map: EQPlotMap
    ) {
        let dotRadius: CGFloat = 4.0
        for (freq, gain) in eqValues {
            let center = CGPoint(x: map.x(forFreq: freq), y: map.y(forGain: gain))
            let dotPath = Path(ellipseIn: CGRect(
                x: center.x - dotRadius, y: center.y - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2
            ))
            context.fill(dotPath, with: .color(Color.asAccent))
        }
    }

    /// Highlight the keyboard-targeted band (A-H1) as a vertical "selected frequency column" — not a
    /// ring on the data point. A full-height column at the band's x reads as a column selection
    /// regardless of the band's gain (the band's own dot sits within it), so it can never look
    /// detached from a dot. Uses the map's log-frequency x, same as the dots.
    func drawKeyboardCursor(context: inout GraphicsContext, map: EQPlotMap, bandIndex: Int) {
        guard EQBands.nominalHz.indices.contains(bandIndex) else { return }
        let xPos = map.x(forFreq: EQBands.nominalHz[bandIndex])

        let stripWidth: CGFloat = 10
        let strip = Path(CGRect(
            x: xPos - stripWidth / 2, y: map.top,
            width: stripWidth, height: map.height
        ))
        context.fill(strip, with: .color(Color.asAccent.opacity(0.15)))

        var centerLine = Path()
        centerLine.move(to: CGPoint(x: xPos, y: map.top))
        centerLine.addLine(to: CGPoint(x: xPos, y: map.bottom))
        context.stroke(centerLine, with: .color(Color.asAccent.opacity(0.6)), lineWidth: 1)
    }

    // MARK: - Interpolation & Smoothing (log-frequency space)

    /// Sample the band curve across the plot in LOG-frequency space, then lightly smooth it. Returns
    /// `(logFreq, gain)` pairs so the caller maps x straight from `logFreq` — no freq round-trip, so
    /// the endpoints stay exactly on the band range.
    private func interpolateFrequencyResponse(
        _ isoPoints: [(freq: Double, gain: Double)]
    ) -> [(logFreq: Double, gain: Double)] {
        guard let first = isoPoints.first, let last = isoPoints.last else { return [] }
        let logMin = log10(first.freq)
        let logMax = log10(last.freq)
        let numSteps = 120

        let logFreqs = (0 ... numSteps).map { step in
            logMin + Double(step) / Double(numSteps) * (logMax - logMin)
        }
        let smoothed = smoothGains(logFreqs.map { gainAtLogFrequency($0, from: isoPoints) }, tapCount: 3)
        return zip(logFreqs, smoothed).map { (logFreq: $0, gain: $1) }
    }

    /// Piecewise-linear (in log-frequency) gain between the two bracketing band centres. `logFreq` is
    /// always within the band range (the interpolation builds it there), so the endpoints resolve
    /// exactly to the first / last band gain — the reason the curve now ends on the 20 Hz / 20 kHz dot.
    private func gainAtLogFrequency(
        _ logFreq: Double,
        from isoPoints: [(freq: Double, gain: Double)]
    ) -> Double {
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
        guard logUpper > logLower else { return lower.gain }
        let position = min(max((logFreq - logLower) / (logUpper - logLower), 0), 1)
        return lower.gain + position * (upper.gain - lower.gain)
    }

    private func smoothGains(_ gains: [Double], tapCount: Int) -> [Double] {
        guard gains.count >= tapCount else { return gains }

        let halfTap = tapCount / 2
        var smoothed = gains

        // Preserve the first / last samples so the curve reaches the 20 Hz / 20 kHz dots exactly; a
        // boundary moving average would otherwise pull the endpoint toward its inner neighbour.
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
