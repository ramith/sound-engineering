import SwiftUI

/// Pure-Mode (bit-perfect HAL output) control: a toggle for user intent plus a live
/// signal-path readout (polled into `AudioViewModel.signalPath` at the spectrum-timer
/// rate). The toggle records intent only; it takes effect on the next track / play.
struct PureModeSettingsSection: View {
    @Bindable var audioViewModel: AudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pure Mode (Bit-Perfect)")
                .font(.headline)
                .foregroundStyle(Color.asLabel)
                .padding(.horizontal, 16)

            Toggle(isOn: $audioViewModel.pureModeEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bit-perfect HAL output")
                        .font(.body)
                        .foregroundStyle(Color.asLabel)
                    Text("DSP/EQ bypassed, bit-perfect HAL output, per-track rate match. "
                        + "Applies on the next track / play.")
                        .font(.caption)
                        .foregroundStyle(Color.asLabelTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(Color.asAccent)
            .padding(.horizontal, 16)

            SignalPathStatusCard(
                info: audioViewModel.signalPath,
                requested: audioViewModel.pureModeEnabled
            )
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Signal-path status card

/// Compact live readout of the achieved signal path. Private to this file.
/// Shows: Active path, Format, Decoder — omits Exclusive (always false) and Decision.
private struct SignalPathStatusCard: View {
    let info: SignalPathInfo
    let requested: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow(label: "Active path", value: pathText, accent: info.path == .pure)
            statusRow(label: "Format", value: formatText)
            statusRow(label: "Decoder", value: decoderText)

            if info.fellBackToEnhanced {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignSystem.Color.statusWarning)
                    Text("Pure requested but not available on this device/track — using Enhanced.")
                        .font(.caption)
                        .foregroundStyle(Color.asLabelSecond)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            } else if requested && info.path != .pure {
                Text("Pure enabled — will engage when the next track starts.")
                    .font(.caption)
                    .foregroundStyle(Color.asLabelTertiary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.asCard)
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5)
        }
    }

    private func statusRow(label: String, value: String, accent: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.asLabelTertiary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(accent ? Color.asAccent : Color.asLabel)
            Spacer()
        }
    }

    private var pathText: String {
        info.path == .pure ? "Pure (HAL-direct)" : "Enhanced (AVAudioEngine)"
    }

    private var decoderText: String {
        switch info.decoder {
        case .some(.ffmpeg): return "FFmpeg"
        case .some(.apple): return "Apple ExtAudioFile"
        case .none: return "—"
        }
    }

    private var formatText: String {
        guard info.achievedSampleRate > 0 else { return "—" }
        // Rate and bit-depth formatted via shared SignalPathInfo helpers — same output as the badge.
        let rateStr = info.formattedRate
        guard let bitsStr = info.formattedBits else { return rateStr }
        return "\(rateStr) · \(bitsStr)"
    }
}
