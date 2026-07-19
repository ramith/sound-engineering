import DesignTokenKit
import SwiftUI

// MARK: - Loudness Meters

/// Read-only BS.1770-5 loudness readout, realigned (S10.8 PR E — `png/05`): three rows of
/// label + slim gradient meter + right-aligned mono value. Integrated / Short-term are
/// LUFS; the third row is inter-sample TRUE peak in dBTP (the label is honest — the C
/// bridge now runs the limiter's 8× polyphase ISP kernel, founder decision 3). Above
/// −1 dBTP the meter tail and value turn amber (`meterHot`, audited R4-METER-01).
struct LoudnessMetersView: View {
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        let snapshot = viewModel.loudness
        let hot = snapshot.hasSignal && snapshot.truePeakDb > DesignSystem.Meters.hotThresholdDbtp
        VStack(alignment: .leading, spacing: 8) {
            Text("Loudness")
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.asLabelSecond)

            MeterRow(label: "Integrated",
                     valueText: lufsText(snapshot.integratedLufs, hasSignal: snapshot.hasSignal),
                     fraction: lufsFraction(snapshot.integratedLufs, hasSignal: snapshot.hasSignal),
                     hot: false,
                     spokenSuffix: "")
            MeterRow(label: "Short-term",
                     valueText: lufsText(snapshot.shortTermLufs, hasSignal: snapshot.hasSignal),
                     fraction: lufsFraction(snapshot.shortTermLufs, hasSignal: snapshot.hasSignal),
                     hot: false,
                     spokenSuffix: "")
            MeterRow(label: "True peak",
                     valueText: truePeakText(snapshot),
                     fraction: truePeakFraction(snapshot),
                     hot: hot,
                     // Non-color cue for the hot state (A-M5 posture): the spoken value
                     // names the ceiling; sighted users get the amber tail + value.
                     spokenSuffix: hot ? ", above the −1 dBTP ceiling" : "")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Loudness meters")
    }

    private func lufsText(_ lufs: Double, hasSignal: Bool) -> String {
        guard hasSignal else { return "—" }
        return "\(lufs.formatted(.number.precision(.fractionLength(1)))) LUFS"
    }

    /// Meter fill for a LUFS value: 0 at the −42 floor → 1 at 0 LUFS (the mock's mapping).
    private func lufsFraction(_ lufs: Double, hasSignal: Bool) -> Double {
        guard hasSignal else { return 0 }
        let floor = DesignSystem.Meters.lufsFloor
        return min(max((lufs - floor) / (0 - floor), 0), 1)
    }

    private func truePeakText(_ snapshot: LoudnessSnapshot) -> String {
        guard snapshot.hasSignal else { return "—" }
        return "\(snapshot.truePeakDb.formatted(.number.precision(.fractionLength(1)))) dBTP"
    }

    private func truePeakFraction(_ snapshot: LoudnessSnapshot) -> Double {
        guard snapshot.hasSignal else { return 0 }
        let floor = DesignSystem.Meters.truePeakFloorDb
        return min(max((snapshot.truePeakDb - floor) / (0 - floor), 0), 1)
    }
}

// MARK: - Meter row (label · slim gradient bar · mono value)

private struct MeterRow: View {
    let label: String
    let valueText: String
    let fraction: Double
    let hot: Bool
    let spokenSuffix: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(DesignSystem.Font.caption)
                .foregroundStyle(Color.asLabelSecond)
                .frame(width: DesignSystem.Meters.labelColumnWidth, alignment: .leading)

            // The shared carved groove (same primitive as the sliders/scrubber), no glow —
            // a readout, not a control. Hot swaps to the teal→amber tail gradient.
            CarvedGroove(fillFraction: fraction,
                         fillStyle: hot ? AnyShapeStyle(DesignSystem.Gradient.meterHotFill)
                             : AnyShapeStyle(DesignSystem.Gradient.meterFill),
                         glow: false)
                .frame(height: CGFloat(GlassDecor.carvedTrackHeight))

            Text(valueText)
                .font(DesignSystem.Font.monoSmall.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(hot ? DesignSystem.Color.meterHotText : Color.asLabel)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(valueText)\(spokenSuffix)")
    }
}
