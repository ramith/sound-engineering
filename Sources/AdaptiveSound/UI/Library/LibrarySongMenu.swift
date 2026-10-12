import LibraryStore
import SwiftUI

// MARK: - Song row menu (S10.8 E1 on Songs; shared with the detail pages in E2)

/// A song row's context menu — Songs and the album, artist and genre pages: Play, Play Next, Add to
/// Queue, Add to Playlist, Info. Each item decides what it acts on when CHOSEN (`targets`): the
/// shown selection when the clicked row is one of several selected rows on screen, else the clicked
/// row alone — whose Play is the row's own (on Songs, the song; on a page, the page from it,
/// decision 11). A selected row a filter or a reload hid never counts (S10.8 E break-it 10). A list
/// builds the menu with every row it builds, so building it does no work: the decision walks the
/// rows only once an item is chosen (the S10.8 End-key hang).
struct LibrarySongMenu: View {
    /// The songs a chosen item acts on: the shown selection, or the clicked row alone.
    let targets: () -> [LibraryTrackDisplay]
    /// Play on the clicked row alone: on Songs, just that song; on a page, the page from that song
    /// on (decision 11).
    let playClicked: () -> Void
    /// Opens the Info popover for a song.
    let showInfo: (LibraryTrackDisplay?) -> Void
    /// "Add to Playlist…": the host's searchable picker, for these songs.
    let choosePlaylist: ([Int64]) -> Void

    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        Button("Play", action: play)
        Button("Play Next") { model.playNext(targets()) }
        Button("Add to Queue") { model.append(targets()) }
        Divider()
        AddToPlaylistMenu(resolveTrackIDs: { targets().map(\.id) }, onChooseMore: choosePlaylist)
        Divider()
        Button("Info", systemImage: "info.circle") { showInfo(targets().first) }
    }

    /// Several shown songs: those, from the first. The clicked row alone: its own Play.
    private func play() {
        let songs = targets()
        if songs.count > 1 {
            model.play(songs, startAt: 0)
        } else {
            playClicked()
        }
    }
}
