import SwiftUI

// MARK: - EQ Controls Section

struct EQControlsSection: View {
    let eqViewModel: EQViewModel
    @Binding var isUsingDiscreteSteps: Bool

    @State private var showSaveSheet = false

    var body: some View {
        // Grid aligns control rows on a shared leading label column; the
        // pickers themselves use .labelsHidden() so the label is shown once here.
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                rowLabel("Preset")
                EQPresetPickerView(eqViewModel: eqViewModel)
            }
            GridRow {
                rowLabel("Interpolation")
                EQInterpolationPickerView(isUsingDiscreteSteps: $isUsingDiscreteSteps)
            }
            GridRow {
                rowLabel("Custom")
                saveButton
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .sheet(isPresented: $showSaveSheet) {
            SaveCustomPresetView(eqViewModel: eqViewModel, isPresented: $showSaveSheet)
        }
    }

    // MARK: - Subviews

    private var saveButton: some View {
        Button("Save as Custom\u{2026}") {
            showSaveSheet = true
        }
        .disabled(eqViewModel.selectedPreset != nil)
        .help(eqViewModel.selectedPreset != nil
            ? "Edit the EQ bands first, then save."
            : "Save the current band state as a named custom preset.")
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
