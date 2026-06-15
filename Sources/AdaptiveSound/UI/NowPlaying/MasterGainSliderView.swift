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
                Text("\(Text(dbValue, format: .number.precision(.fractionLength(1)))) dB")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.asLabelSecond)
            }

            Slider(value: $vm.masterGain, in: 0 ... 1, step: 0.01)
                .tint(Color.asAccent)
                .accessibilityLabel("Master Gain")
                .accessibilityValue(
                    "\(Double(vm.masterGain) * 20 - 10, format: .number.precision(.fractionLength(1))) decibels"
                )
        }
    }
}
