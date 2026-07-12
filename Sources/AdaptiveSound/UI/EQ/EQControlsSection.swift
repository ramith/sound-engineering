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
            threeRow
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

    /// Final fallback when even the two-row layout can't fit (extreme Dynamic
    /// Type, or a content region narrower than the design's 848pt baseline —
    /// design §11.2). One control per row, label-leading/control-trailing on
    /// the SAME row, so no row ever needs more than one control's width —
    /// correct by construction, not by width arithmetic (§11.3).
    private var threeRow: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            // `LabeledContent` (as in `leadingCluster`), NOT an HStack + `.accessibilityElement`
            // `.combine`: `.combine` merges the label and the operable Picker into one element, which
            // can collapse the picker's adjustability for VoiceOver. LabeledContent associates the
            // label with the control while leaving it independently operable (review L9). Each control
            // is alone on its row here, so it has ample width.
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

            HStack {
                Spacer()
                saveButton
            }
        }
    }

    /// Interpolation, then Preset — founder override (design §0).
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
        Button {
            showSaveSheet = true
        } label: {
            Text("Save as Custom\u{2026}")
                .lineLimit(1)
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
    ///
    /// Never wraps (design §11.1): `.fixedSize(horizontal:vertical:)` +
    /// `.lineLimit(1)` force the label to report its own unwrapped ideal width
    /// regardless of how little space the parent proposes back, so under
    /// extreme compression it clips at a fixed single-line height instead of
    /// wrapping into a vertical column of character fragments. Applied once
    /// here so it protects every row tier (`singleRow`/`twoRow`/`threeRow`)
    /// and any future label added to this control bar.
    private func controlLabel(_ title: String) -> some View {
        Text(title)
            .font(DesignSystem.Font.caption)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .fixedSize(horizontal: true, vertical: false)
            .lineLimit(1)
    }
}
