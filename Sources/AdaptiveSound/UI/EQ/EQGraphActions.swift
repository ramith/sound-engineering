import SwiftUI

// MARK: - EQ graph card actions (Sprint EQ, EQ3)

/// The graph card's pills: Compare (hold), Reset (back to the preset's own curve) and Save… (the teal
/// primary). Reset and Save need an edit to act on. While Pure plays all three are inert — the EQ's one
/// rule — each pill in its own disabled look.
struct EQGraphActions: View {
    @Environment(EQViewModel.self) private var eq
    @Environment(AudioViewModel.self) private var audio
    /// Opens the Save sheet.
    let save: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            EQCompareButton()
            HeaderPillButton("Reset", systemImage: "arrow.counterclockwise",
                             help: "Back to the preset's own curve", action: eq.reset)
                .disabled(!eq.isEdited)
            Button("Save…", action: save)
                .buttonStyle(.pill)
                .controlSize(.large)
                .disabled(!eq.isEdited)
                .help(eq.isEdited ? "Save this curve as one of My Presets" : "Edit the curve first, then save it")
        }
        .fixedSize()
        .bitPerfectGate(.equalizer, audio.dspRowAvailability, ownDisabledLook: true)
    }
}
