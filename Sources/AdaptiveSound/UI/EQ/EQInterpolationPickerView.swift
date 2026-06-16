import SwiftUI

// MARK: - EQ Interpolation Picker

struct EQInterpolationPickerView: View {
    @Binding var isUsingDiscreteSteps: Bool

    var body: some View {
        // Label is provided by the parent grid row; hide the picker's own label.
        Picker("Interpolation", selection: $isUsingDiscreteSteps) {
            Text("Smooth Curve").tag(false)
            Text("Discrete Steps").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Interpolation mode")
    }
}
