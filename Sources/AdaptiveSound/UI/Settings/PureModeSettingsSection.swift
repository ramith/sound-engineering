import SwiftUI

/// Minimal Pure-Mode (bit-perfect HAL output) control for hardware smoke-testing B3: a toggle for
/// the user intent plus a LIVE signal-path readout (polled into `AudioViewModel.signalPath` at the
/// spectrum-timer rate). This is an INTERIM affordance — the polished signal-path transparency UI is
/// Phase A2. The toggle records intent only; it takes effect on the next track / play.
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
                    Text("DSP/EQ bypassed, exclusive device access, per-track rate match. "
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

/// Compact live readout of the achieved signal path. Private to this file (interim test UI).
private struct SignalPathStatusCard: View {
    let info: SignalPathInfo
    let requested: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow(label: "Path", value: pathText, accent: info.path == .pure)

            if info.path == .pure {
                statusRow(label: "Decision", value: decisionText)
                statusRow(label: "Format", value: formatText)
                statusRow(label: "Exclusive (hog)", value: info.exclusiveHog ? "Yes" : "No")
                statusRow(label: "Rate matched", value: info.rateMatched ? "Yes" : "No")
                statusRow(label: "Decoder", value: decoderText)
            } else {
                statusRow(label: "Engine", value: "AVAudioEngine graph (48 kHz float)")
                if info.fellBackToEnhanced {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Pure requested but not available on this device/track — using Enhanced.")
                            .font(.caption)
                            .foregroundStyle(Color.asLabelSecond)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                } else if requested {
                    Text("Pure enabled — will engage when the next track starts.")
                        .font(.caption)
                        .foregroundStyle(Color.asLabelTertiary)
                }
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

    private var decisionText: String {
        switch info.decision {
        case .fullBitPerfect: return "Full bit-perfect (integer)"
        case .rateMatchedFloat: return "Rate-matched float (no SRC)"
        case .fallbackEnhanced: return "Fallback"
        }
    }

    private var decoderText: String {
        switch info.decoder {
        case .some(.ffmpeg): return "FFmpeg"
        case .some(.apple): return "Apple ExtAudioFile"
        case .none: return "—"
        }
    }

    private var formatText: String {
        let rateHz = Int(info.achievedSampleRate.rounded())
        let kind = info.isFloat ? "float" : "int"
        return "\(rateHz) Hz • \(info.bitDepth)-bit \(kind)"
    }
}
