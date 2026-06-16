import SwiftUI

// MARK: - EQ Controls Section

struct EQControlsSection: View {
    let eqViewModel: EQViewModel
    @Binding var isUsingDiscreteSteps: Bool

    var body: some View {
        // Grid aligns both control rows on a shared leading label column; the
        // pickers themselves use .labelsHidden() so the label is shown once here
        // (no more duplicate "Interpolation").
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                rowLabel("Preset")
                EQPresetPickerView(eqViewModel: eqViewModel)
            }
            GridRow {
                rowLabel("Interpolation")
                EQInterpolationPickerView(isUsingDiscreteSteps: $isUsingDiscreteSteps)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Color.asLabelTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
            .gridColumnAlignment(.leading)
    }
}
