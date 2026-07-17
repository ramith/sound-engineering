import SwiftUI

// MARK: - Loudness Meters

/// Read-only BS.1770-5 loudness readout (integrated + short-term LUFS) and a
/// sample-peak bar, driven by `AudioViewModel.loudness` (measured on the playback
/// tap by the C++ LufsMeter). Replaces the previously-hardcoded "Active Modules".
struct LoudnessMetersView: View {
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        let snapshot = viewModel.loudness
        VStack(alignment: .leading, spacing: 8) {
            Text("Loudness")
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.asLabelSecond)

            LoudnessReadoutRow(label: "Integrated", lufs: snapshot.integratedLufs,
                               hasSignal: snapshot.hasSignal)
            LoudnessReadoutRow(label: "Short-term", lufs: snapshot.shortTermLufs,
                               hasSignal: snapshot.hasSignal)

            PeakMeterBar(peakDb: snapshot.peakDb)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Loudness meters")
    }
}

// MARK: - LUFS readout row

private struct LoudnessReadoutRow: View {
    let label: String
    let lufs: Double
    let hasSignal: Bool

    private var valueText: String {
        guard hasSignal else { return "—" }
        return "\(lufs.formatted(.number.precision(.fractionLength(1)))) LUFS"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(DesignSystem.Font.caption)
                .foregroundStyle(Color.asLabelSecond)
            Spacer()
            Text(valueText)
                .font(DesignSystem.Font.monoSmall.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.asLabel)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(valueText)")
    }
}

// MARK: - Sample-peak bar (dBFS)

private struct PeakMeterBar: View {
    let peakDb: Double

    private let floorDb: Double = -60
    private let clipDb: Double = -1

    /// 0…1 fill from the floor up to 0 dBFS.
    private var fraction: Double {
        min(max((peakDb - floorDb) / (0 - floorDb), 0), 1)
    }

    private var isHot: Bool {
        peakDb >= clipDb
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Peak")
                .font(DesignSystem.Font.caption)
                .foregroundStyle(Color.asLabelSecond)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.asCard)
                    Capsule()
                        .fill(isHot ? DesignSystem.Color.statusError : Color.asAccent)
                        .frame(width: geo.size.width * CGFloat(fraction))
                }
            }
            .frame(height: 4)

            // Non-color clip cue (A-M5): the bar turning red is the only over-level signal
            // otherwise — invisible to colorblind + VoiceOver users. The word "CLIP" carries it.
            if isHot {
                Text("CLIP")
                    .font(DesignSystem.Font.micro.weight(.bold))
                    .foregroundStyle(DesignSystem.Color.statusErrorText) // text → AA variant (fill above stays vivid)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Peak level")
        .accessibilityValue(peakValueDescription)
    }

    /// Spoken peak level, with the clip state folded into the VoiceOver value (A-M5).
    private var peakValueDescription: String {
        guard peakDb > -100 else { return "silent" }
        let level = "\(peakDb.formatted(.number.precision(.fractionLength(1)))) dBFS"
        return isHot ? "\(level), clipping" : level
    }
}
