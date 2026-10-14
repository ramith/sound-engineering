import LibraryBrowseKit
import SwiftUI

// MARK: - Remove a playlist's missing songs (S10.8 E4 — the app's themed dialog)

/// "Remove 2 missing songs?" — the confirmation before the playlist page's bulk Remove Missing, in the
/// app's themed dialog (`AppDialog`): Cancel the neutral pill and the default (Return, or Esc), Remove
/// the destructive pill. It drops the playlist's entries whose files are gone from disk; there is no
/// undo. `count` is the entries it was asked about that are still missing (`PlaylistDialogLatch`).
///
/// Songs that only can't be reached — their drive unplugged, another drive at its place — are not
/// missing, and are never removed (KI-LIB-01): the dialog says how many stay.
///
/// While the library is being scanned files flicker "missing", so Remove is off and the dialog says
/// why; it comes back when the scan ends.
struct PlaylistRemoveMissingDialog: View {
    /// How many entries Remove will drop.
    let count: Int
    /// How many unavailable entries it keeps: they can't be reached now, which is no sign they're gone.
    let kept: Int
    /// A scan, metadata pass or reconcile is running.
    let isScanning: Bool
    let remove: () -> Void
    let cancel: () -> Void

    private static let consequence = "The playlist entries for files that are missing from disk will be removed. "
        + "This can’t be undone."
    private static let scanning = "Your library is being scanned, and files can look missing until it finishes. "
        + "Remove is available once the scan ends."

    var body: some View {
        AppDialog(title: "Remove \(FacetCountLabel.count(count, noun: "missing song", filtered: false))?",
                  message: message,
                  primary: AppDialogAction(title: "Remove", tone: .destructive, isEnabled: !isScanning,
                                           perform: remove),
                  cancelIsDefault: true, cancel: cancel)
    }

    /// The consequence, then what stays, then — during a scan — why Remove is off.
    private var message: String {
        var paragraphs = [Self.consequence]
        if kept > 0 {
            let songs = FacetCountLabel.count(kept, noun: "song", filtered: false)
            paragraphs.append("\(songs) that can’t be reached right now — their drive may not be connected — "
                + "\(kept == 1 ? "stays" : "stay") in the playlist.")
        }
        if isScanning {
            paragraphs.append(Self.scanning)
        }
        return paragraphs.joined(separator: "\n\n")
    }
}
