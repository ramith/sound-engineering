import SwiftUI

// MARK: - EQ Controls Section

/// The control bar below the frequency-response graph (docs/sprints/eq-controls-redesign.md): the
/// Preset picker leading and "Save as Custom…" trailing, joined by a flexible spacer so the strip
/// uses the available width. `ViewThatFits` reflows to two rows when one can't fit (e.g. large text).
/// The Interpolation (Smooth / Discrete) control left with Sprint EQ: the drag's neighbours always
/// follow (decision 22, `EQStroke`).
struct EQControlsSection: View {
    let eqViewModel: EQViewModel

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
            presetControl
            Spacer(minLength: DesignSystem.Spacing.large)
            saveButton
        }
    }

    /// The fallback: one control per row, label-leading / control-trailing on the SAME row, so no row
    /// ever needs more than one control's width — correct by construction (design §11.3).
    private var twoRow: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            presetControl
            HStack {
                Spacer()
                saveButton
            }
        }
    }

    /// `LabeledContent`, NOT an HStack + `.accessibilityElement(.combine)`: `.combine` merges the
    /// label and the operable Picker into one element, which can collapse the picker's
    /// adjustability for VoiceOver (review L9).
    private var presetControl: some View {
        LabeledContent {
            EQPresetPickerView(eqViewModel: eqViewModel)
                .frame(minWidth: 140)
        } label: {
            controlLabel("Preset")
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
        .disabled(!eqViewModel.isEdited)
        .help(saveHint)
        .accessibilityLabel("Save as Custom Preset")
        .accessibilityHint(saveHint)
    }

    private var saveHint: String {
        eqViewModel.isEdited
            ? "Save the current band state as a named custom preset."
            : "Edit the EQ bands first, then save."
    }

    /// Quiet inline label for a `LabeledContent` control — sentence case, no tracking
    /// (design §4/§6): identifies the control without shouting like a section header.
    ///
    /// Never wraps (design §11.1): `.fixedSize(horizontal:vertical:)` + `.lineLimit(1)` force the
    /// label to report its own unwrapped ideal width regardless of how little space the parent
    /// proposes back, so under extreme compression it clips at a fixed single-line height instead of
    /// wrapping into a vertical column of character fragments.
    private func controlLabel(_ title: String) -> some View {
        Text(title)
            .font(DesignSystem.Font.caption)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .fixedSize(horizontal: true, vertical: false)
            .lineLimit(1)
    }
}
