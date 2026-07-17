import DesignTokenKit
import SwiftUI

// MARK: - Inspector Column (S10.7 PR 5 — founder decision D2: the 8a trailing glass column)

/// The fixed-260pt trailing inspector: master gain, Reimagine intensity, the signal detail
/// line (decoder/bit-depth — relocated from the hero badges per §5), loudness meters, and
/// crossfeed. Content scrolls INSIDE the panel chrome (§5 mandated architecture: the panel's
/// rim/hairline must never scroll away with the content), padded BEFORE the fixed frame (the
/// S9 lesson's PR-5 form: pad-after-frame silently widens the column and steals queue width).
/// Tertiary text is allowed here by the §3.3 placement rule (right side — never the teal core).
struct InspectorColumn: View {
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                MasterGainSliderView()
                ReimagineSectionView()
                signalDetail
                LoudnessMetersView()
                HeadphonesSectionView()
            }
            .padding(14)
        }
        .glassPanel(.panel, in: RoundedRectangle(cornerRadius: CGFloat(GlassDecor.panelRadius),
                                                 style: .continuous))
        .frame(width: CGFloat(NowPlayingLayout.inspectorWidth))
    }

    /// Decoder + bit-depth detail (§5: the audiophile home for what left the hero badges).
    @ViewBuilder
    private var signalDetail: some View {
        let info = viewModel.signalPath
        let parts: [String] = [
            info.formattedBits,
            info.path == .pure ? (info.decoder == .apple ? "Apple decoder"
                : info.decoder == .ffmpeg ? "FFmpeg decoder" : nil) : nil,
        ].compactMap(\.self)
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .accessibilityLabel("Signal detail")
                .accessibilityValue(parts.joined(separator: ", "))
        }
    }
}

// MARK: - Reimagine Intensity Section (moved from NowPlayingInfoView — QW-A)

/// Horizontal carved slider for the global Reimagine intensity knob.
struct ReimagineSectionView: View {
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        @Bindable var bvm = viewModel

        let isPureBypassed = bvm.pureModeEngaged
        let percent = Int((bvm.intensity * 100).rounded())

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Intensity")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.asLabelSecond)

                Spacer()

                if isPureBypassed {
                    Text("Pure (bypassed)")
                        .font(DesignSystem.Font.monoSmall)
                        .foregroundStyle(Color.asLabelTertiary)
                } else {
                    Text("\(percent) %")
                        .font(DesignSystem.Font.monoSmall.weight(.semibold))
                        .foregroundStyle(Color.asLabelSecond)
                }
            }

            CarvedSlider(value: $bvm.intensity,
                         accessibilityLabel: "Reimagine Intensity",
                         accessibilityValueText: "\(percent) percent")
                .disabled(isPureBypassed)
                .help(bvm.intensity == 0 ? "0 % = bit-perfect bypass" : "")

            HStack {
                Text("Bypass")
                    .font(DesignSystem.Font.trackSubtitle)
                    .foregroundStyle(Color.asLabelTertiary)
                Spacer()
                Text("Full Blend")
                    .font(DesignSystem.Font.trackSubtitle)
                    .foregroundStyle(Color.asLabelTertiary)
            }
        }
        .opacity(isPureBypassed ? 0.5 : 1)
    }
}

// MARK: - Headphones Section (moved from NowPlayingInfoView — QW-C)

/// Crossfeed toggle + strength picker; disabled and dimmed on non-headphone devices.
struct HeadphonesSectionView: View {
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        @Bindable var bvm = viewModel

        let isEnabled = bvm.deviceIsHeadphones

        return VStack(alignment: .leading, spacing: 8) {
            Text("Headphones")
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.asLabelSecond)

            if !isEnabled {
                Text("Connect headphones to enable. (On a speaker device the only consequence "
                    + "of crossfeed is a mild, reversible centre-image change — crossfeed is "
                    + "offered here, not auto-applied.)")
                    .font(DesignSystem.Font.trackSubtitle)
                    .foregroundStyle(Color.asLabelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                CrossfeedToggleRow(crossfeedEnabled: $bvm.crossfeedEnabled, deviceEnabled: isEnabled)
                    .fixedSize()
                if bvm.crossfeedEnabled && isEnabled {
                    CrossfeedStrengthPicker(strength: $bvm.crossfeedStrength)
                        .fixedSize()
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Crossfeed Toggle Row

private struct CrossfeedToggleRow: View {
    @Binding var crossfeedEnabled: Bool
    let deviceEnabled: Bool

    var body: some View {
        Toggle(isOn: $crossfeedEnabled) {
            Label("Crossfeed", systemImage: "ear.and.waveform")
                .font(DesignSystem.Font.body)
                .foregroundStyle(Color.asLabel)
        }
        .toggleStyle(.switch)
        .tint(Color.asAccent)
        .disabled(!deviceEnabled)
    }
}

// MARK: - Crossfeed Strength Picker

private struct CrossfeedStrengthPicker: View {
    @Binding var strength: CrossfeedStrength

    var body: some View {
        Picker("Strength", selection: $strength) {
            ForEach(CrossfeedStrength.allCases) { preset in
                Text(preset.displayName).tag(preset)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityLabel("Crossfeed Strength")
    }
}
