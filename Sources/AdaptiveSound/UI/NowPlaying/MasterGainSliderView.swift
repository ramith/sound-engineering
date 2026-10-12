import EQEditKit
import SwiftUI

// MARK: - Master Gain Slider

/// Master Gain (S10.8 G; founder decision 2026-10-12, "Show the real level"): turn-down only, 0 dB at
/// the top, and the readout is the level that plays — the app's gain, or on Pure the output device's
/// own volume (`AudioViewModel.masterGainControl`). The slider moves along `MasterGainLaw`'s dB-linear
/// travel in 1 dB steps.
struct MasterGainSliderView: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        let control = viewModel.masterGainControl

        return VStack(spacing: 8) {
            HStack {
                Text("Master Gain")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.asLabelSecond)

                Spacer()

                if control.isAdjustable {
                    Text(control.readout)
                        .font(DesignSystem.Font.monoSmall.weight(.semibold))
                        .foregroundStyle(Color.asLabelSecond)
                } else {
                    // The Intensity row's Pure look: there is nothing to set here.
                    Text(control.readout)
                        .font(DesignSystem.Font.monoSmall)
                        .foregroundStyle(Color.asLabelTertiary)
                }
            }

            CarvedSlider(
                // Read through the view model, not `control`: two key presses inside one frame must
                // each step from the level the first one set.
                value: Binding(
                    get: { viewModel.masterGainControl.position },
                    set: { viewModel.setMasterGain(position: $0) }
                ),
                step: MasterGainLaw.step,
                accessibilityLabel: "Master Gain",
                accessibilityValueText: control.spoken
            )
            .disabled(!control.isAdjustable)
        }
        .opacity(control.isAdjustable ? 1 : 0.5)
        .help(control.help)
    }
}
