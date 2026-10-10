import DesignTokenKit
import EQEditKit
import SwiftUI

// MARK: - EQ graph painter: the beads, the ceiling ghost, the labels and the drag readout

extension EQGraphPainter {
    /// The active point's radius (`EQPointHandle` is this wide): the ghost's tether ends at its rim.
    static let handleRadius: CGFloat = 7.5

    /// The frequency axis's labelled ticks.
    private static let frequencyLabels: [(hz: Double, text: String)] = [
        (20, "20 Hz"), (50, "50"), (100, "100"), (200, "200"), (500, "500"), (1000, "1k"),
        (2000, "2k"), (5000, "5k"), (10000, "10k"), (20000, "20k"),
    ]

    // MARK: Beads

    /// Calm 31: each point a small bead on the played curve; a point left at 0 dB recedes to a faint
    /// hollow ring. The active point is the handle's, so it gets no bead. Dimmed while nothing plays it.
    func drawBeads(_ context: inout GraphicsContext) {
        let fill = audible.drawsResponse ? DesignSystem.Color.accentFill : DesignSystem.Color.labelTertiary
        for (band, gain) in points.enumerated() where band != activeBand {
            let center = CGPoint(x: x(band: band), y: map.y(forGain: Double(gain)))
            if abs(gain) < 0.25 {
                let ring = CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)
                context.stroke(Path(ellipseIn: ring), with: .color(DesignSystem.Color.labelTertiary), lineWidth: 1)
            } else {
                // A window-coloured halo sets the bead off the curve it sits on.
                let dot = CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
                let halo = Path(ellipseIn: dot.insetBy(dx: -1.25, dy: -1.25))
                context.fill(halo, with: .color(DesignSystem.Color.window))
                context.fill(Path(ellipseIn: dot), with: .color(fill))
            }
        }
    }

    // MARK: The ceiling ghost

    /// A stroke past +12 dB: the point is held at the ceiling, and the level the pointer asked for is
    /// ghosted — a dashed ring there, tethered to the held point. (No dashed "requested" curve: the
    /// designer holds points at ±12, so no honest curve exists for a level the EQ can't play.)
    func drawGhost(_ context: inout GraphicsContext, drag: EQGraphDrag) {
        let held = CGPoint(x: x(band: drag.band), y: map.y(forGain: Self.ceilingDb))
        let asked = CGPoint(x: held.x, y: map.y(forGain: drag.requestedDb))
        let dashed = StrokeStyle(lineWidth: 1.25, dash: [2, 2])
        var tether = Path()
        tether.move(to: CGPoint(x: asked.x, y: asked.y + 5))
        tether.addLine(to: CGPoint(x: held.x, y: held.y - Self.handleRadius))
        context.stroke(tether, with: .color(DesignSystem.Color.labelSecondary), style: dashed)
        let ring = CGRect(x: asked.x - 5, y: asked.y - 5, width: 10, height: 10)
        context.stroke(Path(ellipseIn: ring), with: .color(DesignSystem.Color.labelSecondary), style: dashed)
    }

    // MARK: Labels

    /// The region names above the plot — the Tone regions', each centred over its span, so the graph
    /// and the Tone card name the same five — the dB axis beside it, the frequency axis below it.
    func drawLabels(_ context: inout GraphicsContext) {
        for region in EQToneRegion.allCases {
            let text = Text(region.name.uppercased())
                .font(DesignSystem.Font.micro)
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
            let centreHz = sqrt(region.spanHz.lowerBound * region.spanHz.upperBound) // the middle, on a log axis
            context.draw(context.resolve(text), at: CGPoint(x: map.x(forFreq: centreHz), y: map.top - 6),
                         anchor: .bottom)
        }
        for level in [-12.0, -6, 0, 6, 12] {
            let label = level == 0 ? "0" : level.formatted(.number.sign(strategy: .always()))
            context.draw(context.resolve(axisText(label)), at: CGPoint(x: map.left - 8, y: map.y(forGain: level)),
                         anchor: .trailing)
        }
        for (hz, label) in Self.frequencyLabels {
            let anchor: UnitPoint = hz == 20 ? .topLeading : (hz == 20000 ? .topTrailing : .top)
            context.draw(context.resolve(axisText(label)), at: CGPoint(x: map.x(forFreq: hz), y: map.bottom + 8),
                         anchor: anchor)
        }
    }

    private func axisText(_ label: String) -> Text {
        Text(label)
            .font(DesignSystem.Font.monoMicro)
            .foregroundStyle(DesignSystem.Color.labelTertiary)
    }

    // MARK: The drag readout

    /// The readout over the dragged point: above it, or beside it when the point is held at the ceiling
    /// (above would run into the strip). Kept inside the plot's width.
    func drawTag(_ context: inout GraphicsContext, text: String, band: Int, beside: Bool) {
        let resolved = context.resolve(Text(text)
            .font(DesignSystem.Font.monoSmall.weight(.semibold))
            .foregroundStyle(DesignSystem.Color.label))
        let textSize = resolved.measure(in: CGSize(width: map.width, height: 60))
        let size = CGSize(width: textSize.width + 20, height: textSize.height + 8)
        let point = CGPoint(x: x(band: band), y: map.y(forGain: Double(points[band])))
        let proposed = beside
            ? CGPoint(x: point.x + Self.handleRadius + 10, y: point.y + 10)
            : CGPoint(x: point.x - size.width / 2, y: point.y - Self.handleRadius - 12 - size.height)
        let originX = min(max(proposed.x, map.left), max(map.left, map.right - size.width))
        let box = CGRect(origin: CGPoint(x: originX, y: max(proposed.y, map.top)), size: size)
        let capsule = Path(roundedRect: box, cornerRadius: box.height / 2)
        context.fill(capsule, with: .color(DesignSystem.Color.window))
        context.fill(capsule, with: .color(DesignSystem.Color.from(Palette.panelFill)))
        context.stroke(capsule, with: .color(DesignSystem.Color.from(GlassDecor.glassHairline)), lineWidth: 1)
        context.draw(resolved, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
    }
}
