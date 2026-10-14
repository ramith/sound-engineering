import DesignTokenKit
import EQEditKit
import SwiftUI

// MARK: - Signal-path status (Settings › Pure Mode)

/// Compact live readout of the achieved signal path, at the foot of the Pure Mode card: Playing
/// through, Format, Decoder and EQ Preset — omits Exclusive (always false) and Decision — then why
/// Pure isn't playing yet, when it was asked for (the track or device can't, Master Gain is turned
/// down, or it starts with the next track).
///
/// The labels sit in a fixed column and the values take the rest of the card's width, wrapping rather
/// than truncating (a My Preset's name is the user's own); SLOT-07 holds both at the 880 pt window.
struct SignalPathStatus: View {
    let info: SignalPathInfo
    let requested: Bool
    /// Master Gain's level while Pure waits for it to be back at 0 dB (`pureWaitsForMasterGain`),
    /// else `nil`.
    let waitingAtMasterGain: Float?
    /// Current EQ preset display name ("Flat", "Custom", etc.). Passed in as a
    /// value snapshot so the readout remains a pure function of its inputs.
    let eqPresetName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow(label: "Playing through", value: pathText, accent: info.path == .pure)
            statusRow(label: "Format", value: formatText, spokenValue: formatSpoken)
            statusRow(label: "Decoder", value: decoderText)
            statusRow(label: "EQ Preset", value: eqPresetDisplay)

            if info.fellBackToEnhanced {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignSystem.Color.statusWarningText)
                        .accessibilityHidden(true) // the line says it
                    Text("Pure Mode can’t play this track on this device, so it’s playing Enhanced.")
                        .font(DesignSystem.Font.caption)
                        .foregroundStyle(DesignSystem.Color.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            } else if let level = waitingAtMasterGain {
                Text("Master Gain is turned down (\(MasterGainLaw.text(level))). Pure Mode plays at your "
                    + "device’s own volume, which would be louder, so it waits until Master Gain is back at 0 dB.")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if requested && info.path != .pure {
                Text("Pure Mode starts with the next track.")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A label and its value, read as one element: "Format, 48 kilohertz, 24-bit" — `spokenValue`
    /// where the drawn value reads badly aloud.
    private func statusRow(label: String, value: String, spokenValue: String? = nil,
                           accent: Bool = false) -> some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(spokenValue ?? value)")
    }

    private var pathText: String {
        info.path == .pure ? "Pure" : "Enhanced"
    }

    private var decoderText: String {
        switch info.decoder {
        case .some(.ffmpeg): return "FFmpeg"
        case .some(.apple): return "Apple"
        case .none: return "—"
        }
    }

    private var formatText: String {
        guard info.achievedSampleRate > 0 else { return "—" }
        let rateStr = info.formattedRate
        guard let bitsStr = info.formattedBits else { return rateStr }
        return "\(rateStr) · \(bitsStr)"
    }

    /// `formatText` read aloud: the rate in kilohertz, not "k-H-z", and a pause for the dot.
    private var formatSpoken: String {
        guard info.achievedSampleRate > 0 else { return formatText }
        return [info.spokenRate, info.formattedBits].compactMap(\.self).joined(separator: ", ")
    }

    /// The preset as it plays, or "Off in Pure Mode" while Pure plays (it bypasses the EQ).
    private var eqPresetDisplay: String {
        info.path == .pure ? "Off in Pure Mode" : eqPresetName
    }
}
