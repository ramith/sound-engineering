import SwiftUI

// MARK: - EQ Tab View

struct EQTabView: View {
    @Environment(EQViewModel.self) private var eqViewModel
    @State private var isUsingDiscreteSteps = false

    var body: some View {
        VStack(spacing: 20) {
            FrequencyResponseCanvas(
                eqViewModel: eqViewModel,
                isUsingDiscreteSteps: isUsingDiscreteSteps
            )
            .frame(height: 400, alignment: .center)
            .frame(minWidth: 400)
            .padding(.top, 20)
            .padding(.horizontal)

            EQControlsSection(
                eqViewModel: eqViewModel,
                isUsingDiscreteSteps: $isUsingDiscreteSteps
            )
        }
        .background(Color.asWindow)
        .onChange(of: isUsingDiscreteSteps) { _, newValue in
            eqViewModel.logInterpolationModeChange(newValue)
        }
    }
}
