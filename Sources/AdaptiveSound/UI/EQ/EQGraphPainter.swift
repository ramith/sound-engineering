import DesignTokenKit
import EQEditKit
import SwiftUI

// MARK: - EQ graph painter (Sprint EQ, EQ3 — ui-plan §2 `EQGraph+Drawing`)

/// Everything the EQ graph paints in one Canvas pass, from the state it is handed: the grid, a Tone
/// region's shading, the active band's column, the +12 dB ceiling, the PLAYED curve (EQ1a's designer —
/// never a join of the dots), the 31 beads, the ceiling ghost, the labels and the drag readout. The
/// analyzer silhouette (`EQGraphSilhouette`) and the active point (`EQPointHandle`) are their own views:
/// the silhouette redraws at the analyzer's 20 Hz, the handle's glow is the glass layer's.
///
/// Off, Pure Mode and a held Compare draw what plays — a flat 0 dB — in the dimmed tertiary, with the
/// beads dimmed too; Compare also ghosts the EQ's curve, dashed, so you see what you are missing.
struct EQGraphPainter {
    let map: EQPlotMap
    /// The 31 points, as drawn and sent.
    let points: [Float]
    /// What the EQ plays for `points`; `nil` only if the designer rejected them (then no curve).
    let played: EQPlayed?
    let audible: EQAudibleState
    let highlightedRegion: EQToneRegion?
    /// The band being dragged or under the keyboard cursor: its column, and no bead (the handle's).
    let activeBand: Int?
    let drag: EQGraphDrag?
    /// The drag readout, shown over the dragged point.
    let tag: String?

    /// The EQ's +12 dB ceiling.
    static let ceilingDb = Double(EQBands.pointLimitDb)

    /// The curve's and the flat line's stroke.
    private static let curveStroke = StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)

    func draw(in context: inout GraphicsContext) {
        drawGrid(&context)
        if audible.drawsResponse, let highlightedRegion {
            drawToneShade(&context, region: highlightedRegion)
        }
        if let activeBand {
            drawColumn(&context, band: activeBand)
        }
        drawBandTicks(&context)
        if showsCeiling {
            drawCeiling(&context)
        }
        drawCurve(&context)
        drawBeads(&context)
        if let drag, drag.isPastCeiling {
            drawGhost(&context, drag: drag)
        }
        drawLabels(&context)
        if let tag, let drag {
            drawTag(&context, text: tag, band: drag.band, beside: drag.isPastCeiling)
        }
    }

    /// The x of band `band`'s centre.
    func x(band: Int) -> CGFloat {
        map.x(forFreq: EQBands.nominalHz[band])
    }

    /// The ceiling line shows while the EQ plays and a point sits at +12 dB.
    private var showsCeiling: Bool {
        audible.drawsResponse && points.contains { Double($0) >= Self.ceilingDb - 0.005 }
    }

    // MARK: Grid and washes

    private func drawGrid(_ context: inout GraphicsContext) {
        for level in [-12.0, -6, 6, 12] {
            context.stroke(horizontal(at: level), with: .color(DesignSystem.Color.hairline), lineWidth: 1)
        }
        for freq in [50.0, 100, 200, 500, 1000, 2000, 5000, 10000] {
            var line = Path()
            line.move(to: CGPoint(x: map.x(forFreq: freq), y: map.top))
            line.addLine(to: CGPoint(x: map.x(forFreq: freq), y: map.bottom))
            context.stroke(line, with: .color(DesignSystem.Color.hairline), lineWidth: 0.75)
        }
        // The 0 dB line at full tertiary strength (R4-EQ-02): the reference everything is read against.
        context.stroke(horizontal(at: 0), with: .color(DesignSystem.Color.labelTertiary), lineWidth: 1)
    }

    /// A Tone region's reach: the plot shaded in proportion to how much of a Tone move each frequency
    /// gets (the region's own weights), so exactly its region lights.
    private func drawToneShade(_ context: inout GraphicsContext, region: EQToneRegion) {
        let steps = 60
        let stops = (0 ... steps).map { step in
            let fraction = Double(step) / Double(steps)
            let hz = 20 * pow(1000, fraction) // the plot's log axis, 20 Hz → 20 kHz
            let shade = DesignSystem.Color.from(EQGraphDecor.toneShade).opacity(region.weight(atHz: hz))
            return Gradient.Stop(color: shade, location: fraction)
        }
        context.fill(Path(plotRect), with: .linearGradient(Gradient(stops: stops),
                                                           startPoint: CGPoint(x: map.left, y: 0),
                                                           endPoint: CGPoint(x: map.right, y: 0)))
    }

    /// The active band's column — its whole hit area, between its neighbours' midpoints.
    private func drawColumn(_ context: inout GraphicsContext, band: Int) {
        let centres = EQBands.nominalHz
        let low = band > 0 ? sqrt(centres[band - 1] * centres[band]) : centres[band]
        let high = band < centres.count - 1 ? sqrt(centres[band] * centres[band + 1]) : centres[band]
        let rect = CGRect(x: map.x(forFreq: low), y: map.top,
                          width: map.x(forFreq: high) - map.x(forFreq: low), height: map.height)
        context.fill(Path(rect), with: .color(DesignSystem.Color.from(EQGraphDecor.activeColumn)))
    }

    /// The 31 bands as faint ticks on the floor: where each point lives, without 31 lines.
    private func drawBandTicks(_ context: inout GraphicsContext) {
        for band in points.indices {
            var tick = Path()
            tick.move(to: CGPoint(x: x(band: band), y: map.bottom))
            tick.addLine(to: CGPoint(x: x(band: band), y: map.bottom - 4))
            context.stroke(tick, with: .color(DesignSystem.Color.labelTertiary), lineWidth: 1)
        }
    }

    /// The +12 dB ceiling: an amber dashed line (decision 23, revised by 26).
    private func drawCeiling(_ context: inout GraphicsContext) {
        context.stroke(horizontal(at: Self.ceilingDb), with: .color(DesignSystem.Color.meterHot),
                       style: StrokeStyle(lineWidth: 1.25, dash: [3, 3]))
    }

    // MARK: The curve

    private func drawCurve(_ context: inout GraphicsContext) {
        guard audible.drawsResponse else {
            if audible == .comparing, let played { // what you are missing, ghosted
                context.stroke(responsePath(played), with: .color(DesignSystem.Color.accentFill),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))
            }
            context.stroke(horizontal(at: 0), with: .color(DesignSystem.Color.labelTertiary), style: Self.curveStroke)
            return
        }
        guard let played else { return }
        let line = responsePath(played)
        var area = line
        area.addLine(to: CGPoint(x: map.right, y: map.y(forGain: 0)))
        area.addLine(to: CGPoint(x: map.left, y: map.y(forGain: 0)))
        area.closeSubpath()
        context.fill(area, with: .color(DesignSystem.Color.from(EQGraphDecor.curveArea)))
        context.stroke(line, with: .color(DesignSystem.Color.accentFill), style: Self.curveStroke)
    }

    /// The played response on the designer's 256-point grid.
    private func responsePath(_ played: EQPlayed) -> Path {
        var path = Path()
        for (index, hz) in EQPlayed.frequencies.enumerated() {
            let point = CGPoint(x: map.x(forFreq: hz), y: map.y(forGain: Double(played.responseDb[index])))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    // MARK: Geometry

    var plotRect: CGRect {
        CGRect(x: map.left, y: map.top, width: map.width, height: map.height)
    }

    private func horizontal(at level: Double) -> Path {
        var line = Path()
        line.move(to: CGPoint(x: map.left, y: map.y(forGain: level)))
        line.addLine(to: CGPoint(x: map.right, y: map.y(forGain: level)))
        return line
    }
}
