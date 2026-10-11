import SwiftUI

// MARK: - Delete a playlist (S10.8 E4 — the app's themed dialog)

/// "Delete “Road Trip”?" — the confirmation the rail's Delete… raises for a playlist, in the app's themed
/// dialog (`AppDialog`): Cancel the neutral pill and the default (Return, or Esc), Delete the destructive
/// pill. Only the playlist goes: its songs stay in the library. There is no undo.
struct PlaylistDeleteDialog: View {
    let name: String
    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
        AppDialog(title: "Delete “\(name)”?", message: "Its songs stay in your library. This can’t be undone.",
                  primary: AppDialogAction(title: "Delete", tone: .destructive, perform: delete),
                  cancelIsDefault: true, cancel: cancel)
    }
}
