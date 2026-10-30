import DesignTokenKit
import SettingsKit
import SwiftUI

// MARK: - Inspector Column (S10.7 PR 5 — founder decision D2: the 8a trailing glass column)

/// The fixed-260pt trailing inspector: master gain, Reimagine intensity (hidden until S17 —
/// `AudioViewModel.offersIntensity`), the signal detail line (decoder/bit-depth — relocated from the
/// hero badges per §5), loudness meters, and crossfeed. Content scrolls INSIDE the panel chrome (§5
/// mandated architecture: the panel's rim/hairline must never scroll away with the content), padded
/// BEFORE the fixed frame (the
/// S9 lesson's PR-5 form: pad-after-frame silently widens the column and steals queue width).
/// Tertiary text is allowed here by the §3.3 placement rule (right side — never the teal core).
struct InspectorColumn: View {
    @Environment(AudioViewModel.self) private var viewModel

    /// Measured height of the (padded) content — the FLOATING card (S10.8 PR E) hugs this
    /// instead of stretching to the window bottom; when the region offers less, the
    /// ScrollView scrolls inside the chrome exactly as before.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                MasterGainSliderView()
                if AudioViewModel.offersIntensity {
                    ReimagineSectionView()
                }
                signalDetail
                Hairline()
                LoudnessMetersView()
                Hairline()
                HeadphonesSectionView()
            }
            .padding([.horizontal, .top], 14)
            // A plain bottom inset (unchanged at 24pt). It used to BE the bleed run: the card's
            // bottom light bleed took tertiary text resting on it below AA (4.18 measured —
            // break-it R4), so text was fenced off it. The card no longer carries a bleed
            // (`SurfaceRole.hasBottomBleed`), so every point of it is the audited fill and this
            // is only breathing room under the last control.
            .padding(.bottom, DesignSystem.Spacing.large)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeight = height
            }
        }
        // Content-height floating glass card, shared with the Library rail via
        // `.huggingGlassPanel`: cap at the measured content (top-aligned) — never a fixed
        // height (guide E1) — clip the scrolling content to the panel shape, then paint the
        // panel. Still EXPECTED to scroll at the 640pt window minimum.
        .huggingGlassPanel(contentHeight: contentHeight)
        // The teal radial glow behind/below the card (dark-only — `InspectorCardGlow`) — sits
        // BEHIND the fill strata, bleeding past the bottom edge (the NP inspector's per-card glow;
        // the shared modifier deliberately paints no glow of its own).
        .background { InspectorCardGlow() }
        .frame(width: CGFloat(NowPlayingLayout.inspectorWidth))
        .frame(maxHeight: .infinity, alignment: .top)
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

/// Horizontal carved slider for the global Reimagine intensity knob. Not shown until Intensity's
/// effects are real (FD-2: `AudioViewModel.offersIntensity`); kept whole for S17.
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
                // Sprint EQ decision 25: the EQ plays ahead of the blend, so 0 % is not a bypass.
                .help(bvm.intensity == 0 ? "0 % — Reimagine off (your EQ still plays)" : "")

            // 8a caption row: micro mono under the slider (nearest audited token to the
            // spec's 32%-white is labelTertiary — a bespoke 32% token isn't worth the pair).
            HStack {
                Text("Off")
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

/// Crossfeed toggle + strength picker; disabled on non-headphone devices. The switch shows whether
/// crossfeed plays (`crossfeedPlays`), and sets the listener's choice, which a non-headphone output
/// holds off without switching off. The "Connect headphones" hint is instruction text, so it must
/// stay AA: only the control row dims (`disabledDim`), never the hint or the heading.
///
/// R1.1-B: while Pure plays the row wears the shared "Not in bit-perfect mode" state (US-R1F-20); and on a
/// surround file folded to stereo, where the engine bypasses crossfeed (it is stereo-only until the fold moves
/// into the engine — KI-SND-06), the row says so: "Not active on surround albums" (US-R1F-08 item 7).
struct HeadphonesSectionView: View {
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        @Bindable var bvm = viewModel

        let isEnabled = bvm.deviceIsHeadphones
        let availability = bvm.dspRowAvailability

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
                CrossfeedToggleRow(
                    crossfeedEnabled: Binding(get: { bvm.crossfeedPlays }, set: { bvm.crossfeedEnabled = $0 }),
                    deviceEnabled: isEnabled
                )
                .fixedSize()
                Spacer(minLength: 0)
                if bvm.crossfeedPlays {
                    CrossfeedStrengthPicker(strength: $bvm.crossfeedStrength)
                        .fixedSize()
                }
            }
            .disabledDim(!isEnabled) // the control only (dark 50%, guide E1); light: its own look
            .bitPerfectGate(.crossfeed, availability)

            BitPerfectRowNote(row: .crossfeed, availability: availability, leavePure: bvm.leavePure)
            if bvm.signalPath.crossfeedHeldBySurround {
                Text("Not active on surround albums")
                    .font(DesignSystem.Font.trackSubtitle)
                    .foregroundStyle(Color.asLabelTertiary)
                    .help("Crossfeed works on stereo. A surround file is folded to stereo after it, so it "
                        + "plays without crossfeed.")
            }
        }
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
        }
        .toggleStyle(GlassSwitchStyle()) // label color, tint and the disabled look are the style's
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
