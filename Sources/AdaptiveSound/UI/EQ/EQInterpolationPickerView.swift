import SwiftUI

// MARK: - EQ Interpolation Picker

struct EQInterpolationPickerView: View {
    @Binding var isUsingDiscreteSteps: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("Interpolation")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.asLabelTertiary)
                .textCase(.uppercase)
                .tracking(0.6)

            Picker("Interpolation", selection: $isUsingDiscreteSteps) {
                Text("Smooth Curve").tag(false)
                Text("Discrete Steps").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Interpolation mode")
        }
    }
}
