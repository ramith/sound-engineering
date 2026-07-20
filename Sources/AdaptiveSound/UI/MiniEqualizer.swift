import DesignTokenKit
import SwiftUI

// MARK: - Mini equalizer (S10.8 PR D — realigned `png/04`)

/// Three dancing bars shown in a now-playing row's number slot. Deterministic sine motion
/// (the Realigned Target's spec — supersedes the spectrum-driven plan, recorded in the
/// deviations plan §B); ALL bars rest at `eqBarMinScale` whenever `animating` is false, so
/// pause and Reduce Motion freeze to the same designed still state.
///
/// Shared primitive: the queue/playlist rows (`PlaylistItemRow`) and the Library song list
/// both mount it. Callers own the motion gate — pass
/// `pulseIsActive(isPlaying:reduceMotion:)` so pause AND Reduce Motion freeze the bars.
struct MiniEqualizer: View {
    let animating: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: CGFloat(GlassDecor.eqBarSpacing)) {
            ForEach(GlassDecor.eqBarDurations.indices, id: \.self) { bar in
                EqBar(duration: GlassDecor.eqBarDurations[bar],
                      phase: GlassDecor.eqBarPhases[bar],
                      animating: animating)
            }
        }
        .frame(height: CGFloat(GlassDecor.eqBarContainerHeight))
        .accessibilityHidden(true) // the row's a11y value carries the playing state
    }
}

/// One bar: `TimelineView(.animation(paused:))` + sin — pausing the schedule stops the
/// clock AND the ternary pins the still height, so there is no zombie animation to gate
/// (the §3.4 conditional-animator posture in TimelineView form).
private struct EqBar: View {
    let duration: Double
    let phase: Double
    let animating: Bool

    var body: some View {
        TimelineView(.animation(paused: !animating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let minScale = GlassDecor.eqBarMinScale
            let scale = animating
                ? minScale + (1 - minScale) * (0.5 + 0.5 * sin((time / duration + phase) * 2 * .pi))
                : minScale
            RoundedRectangle(cornerRadius: 1)
                .fill(DesignSystem.Color.accentBright)
                .frame(width: CGFloat(GlassDecor.eqBarWidth))
                .scaleEffect(x: 1, y: scale, anchor: .bottom)
        }
    }
}
