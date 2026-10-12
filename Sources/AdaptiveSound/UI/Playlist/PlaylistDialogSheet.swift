import LibraryBrowseKit
import SwiftUI

// MARK: - Playlist dialog sheet (S10.8 E fix round — the Library tab's ONE playlist dialog host)

/// The Library tab's playlist dialogs, hosted once (`LibraryTabView`): a playlist action's failure —
/// whichever view raised it: the rail's delete or create, an Add to Playlist on any page, the playlist
/// page's remove, Locate, Remove Missing or order save — and the two confirmations, the rail's Delete…
/// and the playlist page's Remove Missing…. ONE sheet over the model's one latched value
/// (`PlaylistsModel.dialog`, a `PlaylistDialogLatch`), so two dialogs never ask for the window at
/// once; in the app's themed dialog (the window's own modality, not the system alert).
struct PlaylistDialogSheet: ViewModifier {
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(LibraryBrowseModel.self) private var browse

    func body(content: Content) -> some View {
        content.sheet(item: dialog) { dialog in
            switch dialog {
            case let .failure(message):
                PlaylistFailureNotice(message: message, dismiss: playlists.dismissFailure)
            case let .confirmDelete(_, name):
                PlaylistDeleteDialog(name: name, delete: deletePlaylist, cancel: playlists.cancelConfirmation)
            case let .confirmRemoveMissing(entries):
                PlaylistRemoveMissingDialog(count: entries.count, isScanning: playlists.isLibraryPopulating,
                                            remove: removeMissing, cancel: playlists.cancelConfirmation)
            }
        }
    }

    /// The latch's dialog, read-only. The sheet closes through the latch's own verbs alone — every
    /// button and key of an `AppDialog` is one — so a write from SwiftUI is ignored: a late one could
    /// otherwise swallow a failure that had just taken the sheet (Remove, then the store failing).
    private var dialog: Binding<PlaylistDialog?> {
        Binding(get: { playlists.dialog }, set: { _ in })
    }

    /// Delete: delete the confirmed playlist and, if its page is the one showing — read AFTER the
    /// delete, so a user who moved on is not pulled back — leave it for the category, as the user
    /// left it (its Filter text and place), not a rail jump. The model closes the page's detail and
    /// returns in the same turn, so no frame shows the page closed. A failed delete stays put (the
    /// failure notice says why).
    private func deletePlaylist() {
        Task {
            guard let deleted = await playlists.confirmDelete() else { return }
            if browse.sidebarSelection == .playlist(deleted) {
                browse.showCategoryRoot()
            }
        }
    }

    private func removeMissing() {
        Task { await playlists.confirmRemoveMissing() }
    }
}

extension View {
    /// Host the Library tab's playlist dialogs here (`PlaylistDialogSheet`) — once per window.
    func playlistDialogSheet() -> some View {
        modifier(PlaylistDialogSheet())
    }
}
