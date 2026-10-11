import SwiftUI

// MARK: - Playlist ⋯ menu (S10.8 E4 — the playlist header's third pill)

/// The playlist header's ⋯ (`LibraryPageMoreMenu`, every Library page's ⋯ pill): Play Next and Add to
/// Queue for the whole playlist, and, while some of its files are missing, Remove Missing… (the page
/// confirms it; off during a scan, when files flicker "missing").
struct PlaylistMoreMenu: View {
    /// Asks to remove the entries whose files are missing.
    let removeMissing: () -> Void

    @Environment(PlaylistsModel.self) private var model

    var body: some View {
        LibraryPageMoreMenu {
            Button("Play Next", action: playNext)
            Button("Add to Queue", action: addToQueue)
            if model.missingEntryCount > 0 {
                Divider()
                Button("Remove \(model.missingEntryCount.formatted(.number)) Missing…", role: .destructive,
                       action: removeMissing)
                    .disabled(model.isLibraryPopulating)
            }
        }
    }

    private func playNext() {
        model.playPlaylistNext()
    }

    private func addToQueue() {
        model.appendPlaylist()
    }
}
