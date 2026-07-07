import SwiftUI

// MARK: - EQ Controls Section

/// Single control-bar layout for the EQ tab, below the frequency-response graph
/// (docs/sprints/eq-controls-redesign.md). Leading cluster — Interpolation, then
/// Preset (founder override, §0) — plus a trailing "Save as Custom…" action,
/// joined by a flexible spacer so the strip uses the available width instead of
/// hugging the leading edge. `ViewThatFits` reflows to a two-row fallback when the
/// single row can't fit (e.g. large Dynamic Type inflating the segment titles).
struct EQControlsSection: View {
    let eqViewModel: EQViewModel
    @Binding var isUsingDiscreteSteps: Bool

    @State private var showSaveSheet = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            singleRow
            twoRow
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .sheet(isPresented: $showSaveSheet) {
            SaveCustomPresetView(eqViewModel: eqViewModel, isPresented: $showSaveSheet)
        }
    }

    // MARK: - Row layouts

    private var singleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            leadingCluster
            Spacer(minLength: DesignSystem.Spacing.large)
            saveButton
        }
    }

    private var twoRow: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            leadingCluster
            HStack {
                Spacer()
                saveButton
            }
        }
    }

    /// Interpolation, then Preset — founder order override (design §0).
    private var leadingCluster: some View {
        HStack(spacing: DesignSystem.Spacing.large) {
            LabeledContent {
                EQInterpolationPickerView(isUsingDiscreteSteps: $isUsingDiscreteSteps)
                    .fixedSize()
            } label: {
                controlLabel("Interpolation")
            }

            LabeledContent {
                EQPresetPickerView(eqViewModel: eqViewModel)
                    .frame(minWidth: 140)
            } label: {
                controlLabel("Preset")
            }
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
        .accessibilityLabel("Save as Custom Preset")
        .accessibilityHint(eqViewModel.selectedPreset != nil
            ? "Edit the EQ bands first, then save."
            : "Save the current band state as a named custom preset.")
    }

    /// Quiet inline label for a `LabeledContent` control — sentence case, no tracking
    /// (design §4/§6): identifies the control without shouting like a section header.
    private func controlLabel(_ title: String) -> some View {
        Text(title)
            .font(DesignSystem.Font.caption)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
    }
}
