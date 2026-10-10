import EQEditKit
import SwiftUI

// MARK: - Save / Rename preset sheet (Sprint EQ, EQ4)

/// The sheet that names one of My Presets: Save (the curve that played when the sheet opened, into the
/// slot it came from — break-it C1) or Rename. It shows the curve the preset will play, and checks the
/// name as it is typed (`EQPresetName`): a built-in's name, in any case, is refused (N1), and so is a
/// name of spaces or line breaks alone (N2), each with a line saying why; a Save onto one of My Presets
/// says it replaces it. Save / Rename stays disabled until the name will do.
///
/// Presented by the EQ tab: Save from the graph card's "Save…" and My Presets' "+" (both enabled only
/// while the EQ is edited); Rename from a My Preset's menu, VoiceOver action or Return in the list.
struct SaveCustomPresetView: View {
    let sheet: EQPresetSheet
    let eqViewModel: EQViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var presetName: String
    @FocusState private var nameFocused: Bool

    init(sheet: EQPresetSheet, eqViewModel: EQViewModel) {
        self.sheet = sheet
        self.eqViewModel = eqViewModel
        if case let .rename(name) = sheet {
            _presetName = State(initialValue: name)
        } else {
            _presetName = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: DesignSystem.Spacing.small) {
                EQCurveGlyph(points: points)
                Text(title)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                TextField("Preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    // Focus + the transport-Space gate (S4 SW1) in one place; auto-focus so the sheet
                    // is type-ready on appear.
                    .suppressesTransportSpace(while: $nameFocused)
                    .onAppear { nameFocused = true }
                    .onSubmit(commit)
                // The line keeps its room when empty, so the sheet doesn't jump; VoiceOver reads it
                // whenever it says something, and hears it as it appears or changes.
                Text(note ?? " ")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(noteColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(note == nil)
                    .onChange(of: note) { _, line in announce(line) }
            }

            HStack {
                Spacer()
                Button("Cancel", action: dismissSheet)
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCommit)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    // MARK: Derived

    private var renaming: String? {
        if case let .rename(name) = sheet {
            return name
        }
        return nil
    }

    private var title: String {
        renaming.map { "Rename “\($0)”" } ?? "Save Preset"
    }

    private var actionTitle: String {
        renaming == nil ? "Save" : "Rename"
    }

    /// The curve the preset will play: what is being saved, or the preset being renamed.
    private var points: [Float] {
        switch sheet {
        case let .save(source): source.state.points
        case let .rename(name): eqViewModel.glyphPoints(for: .mine(name))
        }
    }

    private var check: EQPresetName.Check {
        eqViewModel.nameCheck(presetName, renaming: renaming)
    }

    private var canCommit: Bool {
        if case .invalid = check {
            return false
        }
        return true
    }

    /// The line under the field: why a name won't do, or that Save replaces a preset. Nothing for an
    /// empty field — Save is simply disabled until something is typed.
    private var note: String? {
        switch check {
        case let .invalid(problem): presetName.isEmpty ? nil : problem.message
        case let .replaces(existing): "Saving replaces your preset “\(existing)”."
        case .new: nil
        }
    }

    private var noteColor: Color {
        if case .invalid = check {
            return DesignSystem.Color.statusErrorText
        }
        return DesignSystem.Color.labelSecondary
    }

    // MARK: Actions

    private func commit() {
        guard canCommit else { return }
        switch sheet {
        case let .save(source): eqViewModel.save(source, as: presetName)
        case let .rename(name): eqViewModel.renameMyPreset(name, to: presetName)
        }
        dismiss()
    }

    private func dismissSheet() {
        dismiss()
    }

    private func announce(_ line: String?) {
        guard let line else { return }
        AccessibilityNotification.Announcement(line).post()
    }
}
