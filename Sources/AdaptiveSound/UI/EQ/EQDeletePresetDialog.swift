import SwiftUI

// MARK: - Delete a My Preset (Sprint EQ, EQ4; the founder's "match the UI theme")

/// "Delete “Late Night”?" — the confirmation ⌫ and the menu's Delete… raise for one of My Presets, in
/// the app's themed dialog: Cancel the neutral pill and the default (Return, or Esc), Delete the
/// destructive pill. Whatever plays the preset keeps its sound, as an edited Flat.
struct EQDeletePresetDialog: View {
    let name: String
    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
        AppDialog(title: "Delete “\(name)”?", message: "Whatever plays it now keeps its sound.",
                  primary: AppDialogAction(title: "Delete", tone: .destructive, perform: delete),
                  cancelIsDefault: true, cancel: cancel)
    }
}
