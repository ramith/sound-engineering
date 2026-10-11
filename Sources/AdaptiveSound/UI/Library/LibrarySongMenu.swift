import LibraryStore
import SwiftUI

// MARK: - Song row menu (S10.8 E1 on Songs; shared with the detail pages in E2)

/// A song row's context menu — Songs and the album, artist and genre pages: Play, Play Next, Add to
/// Queue, Add to Playlist, Info. It acts on the whole selection when the clicked row is one of
/// several selected (`ListSelection.menuActsOnSelection`), else on the clicked row. A list builds
/// it with every row it builds, so it does O(1) work: the selection's songs are resolved only when
/// an item is CHOSEN (the S10.8 End-key hang).
struct LibrarySongMenu: View {
    let clicked: LibraryTrackDisplay
    /// The menu acts on the selection, not the clicked row alone.
    let actsOnSelection: Bool
    /// The selected songs in display order — resolved when an item is chosen.
    let selectedTracks: () -> [LibraryTrackDisplay]
    /// Play on the clicked row alone: on Songs, just that song; on a page, the page from that song
    /// on (decision 11).
    let playClicked: () -> Void
    /// Opens the Info popover for a song.
    let showInfo: (LibraryTrackDisplay?) -> Void
    /// "Add to Playlist…": the host's searchable picker, for these songs.
    let choosePlaylist: ([Int64]) -> Void

    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        if actsOnSelection {
            Button("Play") { model.play(selectedTracks(), startAt: 0) }
            Button("Play Next") { model.playNext(selectedTracks()) }
            Button("Add to Queue") { model.append(selectedTracks()) }
            Divider()
            AddToPlaylistMenu(resolveTrackIDs: { selectedTracks().map(\.id) }, onChooseMore: choosePlaylist)
            Divider()
            Button("Info", systemImage: "info.circle") { showInfo(selectedTracks().first) }
        } else {
            Button("Play", action: playClicked)
            Button("Play Next") { model.playNext([clicked]) }
            Button("Add to Queue") { model.append([clicked]) }
            Divider()
            AddToPlaylistMenu(resolveTrackIDs: { [clicked.id] }, onChooseMore: choosePlaylist)
            Divider()
            Button("Info", systemImage: "info.circle") { showInfo(clicked) }
        }
    }
}
