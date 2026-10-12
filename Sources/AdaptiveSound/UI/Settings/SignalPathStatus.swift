import DesignTokenKit
import SwiftUI

// MARK: - Signal-path status (Settings › Pure Mode)

/// Compact live readout of the achieved signal path, at the foot of the Pure Mode card: Active path,
/// Format, Decoder and EQ Preset — omits Exclusive (always false) and Decision — then why Pure isn't
/// playing yet, when it was asked for.
///
/// The labels sit in a fixed column and the values take the rest of the card's width, wrapping rather
/// than truncating (a My Preset's name is the user's own); SLOT-07 holds both at the 880 pt window.
struct SignalPathStatus: View {
    let info: SignalPathInfo
    let requested: Bool
    /// Current EQ preset display name ("Flat", "Custom", etc.). Passed in as a
    /// value snapshot so the readout remains a pure function of its inputs.
    let eqPresetName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow(label: "Active path", value: pathText, accent: info.path == .pure)
            statusRow(label: "Format", value: formatText)
            statusRow(label: "Decoder", value: decoderText)
            statusRow(label: "EQ Preset", value: eqPresetDisplay)

            if info.fellBackToEnhanced {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignSystem.Color.statusWarningText)
                        .accessibilityHidden(true) // the line says it
                    Text("Pure requested but not available on this device/track — using Enhanced.")
                        .font(DesignSystem.Font.caption)
                        .foregroundStyle(DesignSystem.Color.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            } else if requested && info.path != .pure {
                Text("Pure enabled — will engage when the next track starts.")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusRow(label: String, value: String, accent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CGFloat(SettingsLayout.statusColumnGap)) {
            Text(label)
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .frame(width: CGFloat(SettingsLayout.statusLabelWidth), alignment: .leading)
            Text(value)
                .font(DesignSystem.Font.caption.monospaced())
                .foregroundStyle(accent ? DesignSystem.Color.accentForeground : DesignSystem.Color.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
        let rateStr = info.formattedRate
        guard let bitsStr = info.formattedBits else { return rateStr }
        return "\(rateStr) · \(bitsStr)"
    }

    /// Show the preset name, or "—" when Pure mode is active (EQ bypassed).
    private var eqPresetDisplay: String {
        info.path == .pure ? "— (Pure bypassed)" : eqPresetName
    }
}
