import DesignTokenKit
import EQEditKit
import SwiftUI

// MARK: - EQ curve glyph (Sprint EQ, EQ3)

/// A preset's shape in miniature — its 31 points across the row's leading column, over a hairline 0 dB,
/// on the graph's own ±12 dB scale so glyphs compare honestly (a gentle +3 dB Presence reads gentle).
/// Decorative: the row's name carries it for VoiceOver.
struct EQCurveGlyph: View {
    let points: [Float]

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let scale = (midY - 1.5) / CGFloat(EQBands.pointLimitDb)
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: midY))
            zero.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(zero, with: .color(DesignSystem.Color.hairline), lineWidth: 1)
            guard points.count > 1 else { return }
            var line = Path()
            for (band, gain) in points.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(band) / CGFloat(points.count - 1),
                                    y: midY - CGFloat(gain) * scale)
                if band == 0 {
                    line.move(to: point)
                } else {
                    line.addLine(to: point)
                }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: midY))
            area.addLine(to: CGPoint(x: 0, y: midY))
            area.closeSubpath()
            context.fill(area, with: .color(DesignSystem.Color.from(EQGraphDecor.curveArea)))
            context.stroke(line, with: .color(DesignSystem.Color.accentFill),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 26, height: 14)
        .accessibilityHidden(true)
    }
}
