import SwiftUI

// MARK: - EQ Controls Section

struct EQControlsSection: View {
    let eqViewModel: EQViewModel
    @Binding var isUsingDiscreteSteps: Bool

    var body: some View {
        VStack(spacing: 10) {
            EQPresetPickerView(eqViewModel: eqViewModel)

            EQInterpolationPickerView(isUsingDiscreteSteps: $isUsingDiscreteSteps)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}
