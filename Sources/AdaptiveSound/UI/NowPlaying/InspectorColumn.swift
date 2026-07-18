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
            .padding([.horizontal, .top], 14)
            // Bottom inset == the bleed run (break-it R4 catch): the dark-only bottom light
            // bleed brightens the panel fill enough that tertiary text RESTING on it fails
            // AA (4.18 measured). Reading the same token as the bleed's height means text
            // can never rest on the bleed and the two values cannot drift apart. (Rows still
            // CROSS the run transiently while scrolling — accepted, same class as text
            // passing under the seam feather.)
            .padding(.bottom, CGFloat(GlassDecor.bleedHeight))
        }
        // Clip the SCROLLING content to the panel's shape: `.glassPanel` paints fill under
        // and strokes over but never clips, so rows crossing the top/bottom edge would
        // render square into the radius-22 corner cutouts (~6pt intrusion) — and this
        // panel is EXPECTED to scroll at the 640pt window minimum.
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(GlassDecor.panelRadius),
                                    style: .continuous))
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

// MARK: - Reimagine Intensity Section (QW-A)

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

            // 8a caption row: micro mono under the slider (nearest audited token to the
            // spec's 32%-white is labelTertiary — a bespoke 32% token isn't worth the pair).
            HStack {
                Text("Bypass")
                    .font(DesignSystem.Font.monoMicro)
                    .foregroundStyle(Color.asLabelTertiary)
                Spacer()
                Text("Full Blend")
                    .font(DesignSystem.Font.monoMicro)
                    .foregroundStyle(Color.asLabelTertiary)
            }
        }
        .opacity(isPureBypassed ? 0.5 : 1)
    }
}

// MARK: - Headphones Section (QW-C)

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
                // One line + tooltip (deviations §4): the full rationale lives in .help, not
                // permanently on screen.
                Text("Connect headphones to enable.")
                    .font(DesignSystem.Font.trackSubtitle)
                    .foregroundStyle(Color.asLabelTertiary)
                    .help("On a speaker device the only consequence of crossfeed is a mild, "
                        + "reversible centre-image change — crossfeed is offered here, not "
                        + "auto-applied.")
            }

            // ONE row (founder, PR-5 screenshot round): toggle leading, strength picker
            // trailing — the picker joins the row only while crossfeed is on.
            HStack(spacing: DesignSystem.Spacing.small) {
                CrossfeedToggleRow(crossfeedEnabled: $bvm.crossfeedEnabled, deviceEnabled: isEnabled)
                    .fixedSize()
                Spacer(minLength: 0)
                if bvm.crossfeedEnabled && isEnabled {
                    CrossfeedStrengthPicker(strength: $bvm.crossfeedStrength)
                        .fixedSize()
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.55) // 8a disabled-block opacity
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
