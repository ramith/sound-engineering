import LibraryBrowseKit
import SwiftUI

// MARK: - Remove a playlist's missing songs (S10.8 E4 — the app's themed dialog)

/// "Remove 2 missing songs?" — the confirmation before the playlist page's bulk Remove Missing, in the
/// app's themed dialog (`AppDialog`): Cancel the neutral pill and the default (Return, or Esc), Remove
/// the destructive pill. It drops the playlist's entries whose files are gone from disk; there is no undo.
struct PlaylistRemoveMissingDialog: View {
    /// How many entries' files are missing.
    let count: Int
    let remove: () -> Void
    let cancel: () -> Void

    var body: some View {
        AppDialog(title: "Remove \(FacetCountLabel.count(count, noun: "missing song", filtered: false))?",
                  message: "The playlist entries for files that are missing from disk will be removed. "
                      + "This can’t be undone.",
                  primary: AppDialogAction(title: "Remove", tone: .destructive, perform: remove),
                  cancelIsDefault: true, cancel: cancel)
    }
}
