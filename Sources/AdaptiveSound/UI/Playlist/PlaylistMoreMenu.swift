import LibraryBrowseKit
import SwiftUI

// MARK: - Playlist ⋯ menu (S10.8 E4 — the playlist header's third pill)

/// The playlist header's ⋯ (`LibraryPageMoreMenu`, every Library page's ⋯ pill): Play Next and Add to
/// Queue for the whole playlist — each confirmed by the queue toast, as on the album, artist and genre
/// pages — Add Files… (files from anywhere, R1.1-B) and, while some of its files are missing, Remove
/// Missing… (confirmed first, in the Library tab's dialog; off during a scan, when files flicker
/// "missing").
struct PlaylistMoreMenu: View {
    /// Add Files…: choose files from anywhere to add to the playlist (R1.1-B, US-PLIST-02).
    let addFiles: () -> Void

    @Environment(PlaylistsModel.self) private var model
    @Environment(LibraryBrowseModel.self) private var library

    var body: some View {
        LibraryPageMoreMenu {
            Button("Play Next", action: playNext)
            Button("Add to Queue", action: addToQueue)
            Divider()
            Button("Add Files…", action: addFiles)
            if model.missingEntryCount > 0 {
                Divider()
                Button("Remove \(model.missingEntryCount.formatted(.number)) Missing…", role: .destructive,
                       action: model.askToRemoveMissing)
                    .disabled(model.isLibraryPopulating)
            }
        }
    }

    private func playNext() {
        showQueueToast(.playNext, added: model.playPlaylistNext())
    }

    private func addToQueue() {
        showQueueToast(.addToQueue, added: model.appendPlaylist())
    }

    /// The queue toast for `added` songs. None went in when nothing in the playlist is playable: that
    /// stays silent, as an empty page does — never a false "Already in Queue".
    private func showQueueToast(_ verb: QueueVerb, added: Int) {
        guard added > 0 else { return }
        library.showQueueToast(verb, added: added)
    }
}
