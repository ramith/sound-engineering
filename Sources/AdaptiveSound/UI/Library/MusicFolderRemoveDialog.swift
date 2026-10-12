import SwiftUI

// MARK: - Remove a music folder (S10.8 F2 — the app's themed dialog)

/// "Remove "~/Music/Lossless" from your library?" — the confirmation the rail's folder row raises before
/// a music folder leaves the library, in the app's themed dialog (`AppDialog`): Cancel the neutral pill
/// and the default (Return, or Esc), Remove the destructive pill. The audio files stay on disk.
struct MusicFolderRemoveDialog: View {
    /// The folder's path as the row shows it (abbreviated with a tilde).
    let path: String
    let remove: () -> Void
    let cancel: () -> Void

    var body: some View {
        AppDialog(title: "Remove \"\(path)\" from your library?",
                  message: "The audio files on disk aren't deleted. Songs from this folder leave your "
                      + "library unless they're in a playlist.",
                  primary: AppDialogAction(title: "Remove", tone: .destructive, perform: remove),
                  cancelIsDefault: true, cancel: cancel)
    }
}
