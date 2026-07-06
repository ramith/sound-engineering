import SwiftUI

// MARK: - Now Playing Info

/// The now-playing card, live loudness meters, Reimagine intensity knob (QW-A), and headphone
/// crossfeed controls (QW-C). Lives in the Now Playing left panel beneath the spectrum +
/// master-gain controls. (Transport + seek moved to the global footer bar in L3.)
struct NowPlayingInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NowPlayingWidget()
            LoudnessMetersView()
            ReimagineSectionView()
            HeadphonesSectionView()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Reimagine Intensity Section

/// Horizontal slider for the global Reimagine intensity knob (QW-A).
/// Matches the `MasterGainSliderView` layout pattern.
private struct ReimagineSectionView: View {
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        @Bindable var bvm = viewModel

        let isPureBypassed = bvm.pureModeEngaged
        let percentText = Text(
            "\(Int((bvm.intensity * 100).rounded())) %"
        )
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(isPureBypassed ? Color.asLabelTertiary : Color.asLabelSecond)

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
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.asLabelTertiary)
                } else {
                    percentText
                }
            }

            Slider(value: $bvm.intensity, in: 0 ... 1, step: 0.01)
                .tint(Color.asAccent)
                .disabled(isPureBypassed)
                .help(bvm.intensity == 0 ? "0 % = bit-perfect bypass" : "")
                .accessibilityLabel("Reimagine Intensity")
                .accessibilityValue("\(Int((bvm.intensity * 100).rounded())) percent")

            HStack {
                Text("Bypass")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.asLabelTertiary)
                Spacer()
                Text("Full Blend")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.asLabelTertiary)
            }
        }
        .opacity(isPureBypassed ? 0.5 : 1)
    }
}

// MARK: - Headphones Section

/// Crossfeed toggle + strength picker shown when crossfeed is enabled (QW-C).
/// Disabled and dimmed on non-headphone devices (wireless / USB heuristic).
private struct HeadphonesSectionView: View {
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
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.asLabelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                CrossfeedToggleRow(crossfeedEnabled: $bvm.crossfeedEnabled, deviceEnabled: isEnabled)
                    .fixedSize()
                Spacer(minLength: 12)
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
                .font(.system(size: 13, weight: .regular))
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
