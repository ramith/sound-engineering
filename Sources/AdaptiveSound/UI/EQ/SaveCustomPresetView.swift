import SwiftUI

// MARK: - Save Custom Preset Sheet

/// Modal sheet that prompts the user for a name and saves the current
/// 31-band state as a named custom preset in `EQViewModel`.
///
/// Presented from `EQControlsSection` when the user presses "Save as Custom…"
/// (only enabled when `selectedPreset == nil`, i.e. the bands have been edited).
struct SaveCustomPresetView: View {
    let eqViewModel: EQViewModel

    @Binding var isPresented: Bool

    @State private var presetName: String = ""

    private var canSave: Bool {
        !presetName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Custom Preset")
                .font(.headline)

            TextField("Preset name", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    commitSave()
                }

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    commitSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
    }

    private func commitSave() {
        guard canSave else { return }
        eqViewModel.saveCustomPreset(name: presetName)
        isPresented = false
    }
}
