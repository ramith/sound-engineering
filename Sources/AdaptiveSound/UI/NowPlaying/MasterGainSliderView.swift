import SwiftUI

// MARK: - Master Gain Slider

struct MasterGainSliderView: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        return VStack(spacing: 8) {
            HStack {
                Text("Master Gain")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.asLabelSecond)

                Spacer()

                let dbValue = Double(vm.masterGain) * 20 - 10
                // SIGNED readout (8a: "+4.0 dB" — gain direction matters on an audio control).
                Text("\(Text(dbValue, format: .number.precision(.fractionLength(1)).sign(strategy: .always()))) dB")
                    .font(DesignSystem.Font.monoSmall.weight(.semibold))
                    .foregroundStyle(Color.asLabelSecond)
            }

            CarvedSlider(
                value: $vm.masterGain,
                accessibilityLabel: "Master Gain",
                accessibilityValueText: String(format: "%+.1f decibels", Double(vm.masterGain) * 20 - 10)
            )
        }
    }
}
