import LibraryBrowseKit
import SwiftUI

// MARK: - Detail page (S10.8 E2/E3 — the album, artist and genre pages)

/// An album, artist or genre page, on the Library's one card (mounted by `LibraryTabView`, D1 — the
/// page paints no card or background of its own): the header (`LibraryDetailHeader`) over the songs
/// (`DetailTrackList`), or "No Songs" for a page whose songs have all gone. One view for the three
/// pages — they differ only in their content (`LibraryBrowseModel.detailContent`).
///
/// It loads when it opens and again on every library change (`libraryRevision`, once per scan pass),
/// so a page stays true while a scan runs; the list keeps its selection across the reload, by id.
/// It hosts the one "Add to Playlist…" picker its header and rows share.
struct LibraryDetailPage: View {
    let ref: LibraryBrowseModel.FacetRef

    @Environment(LibraryBrowseModel.self) private var model
    @Environment(LibraryModel.self) private var library
    @State private var content: LibraryDetailContent?
    /// Non-nil while the searchable "Add to Playlist…" picker is open.
    @State private var addToPlaylistTarget: AddToPlaylistTarget?
    /// The page's one focus value: the song list is `.content`.
    @FocusState private var focus: CardFocus?
    #if DEBUG
        /// Picture-sheet renderer only (`Debug/SheetFixture+Detail.swift`): the page's fixture content.
        @Environment(\.sheetDetailPage) private var sheetDetailPage
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if let content {
                LibraryDetailHeader(ref: ref, content: content, choosePlaylist: choosePlaylist)
                switch FacetDetailState.state(trackCount: content.layout.rows.count) {
                case .empty:
                    // A reachable page whose songs all left the library (e.g. after a rescan).
                    ContentUnavailableView("No Songs", systemImage: "music.note")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .list:
                    DetailTrackList(layout: content.layout, focus: $focus, choosePlaylist: choosePlaylist)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Keyed on the revision alone: the page is one `ref` for its whole life — the route view gives
        // each page its own identity (`.id(route)`), so another page is a new view, not a new ref.
        .task(id: library.libraryRevision) { await load() }
        .sheet(item: $addToPlaylistTarget) { target in
            PlaylistPickerSheet(trackIDs: target.trackIDs)
        }
    }

    /// Reads the page; a newer load (the next library change) wins — the task it superseded was
    /// cancelled while its read ran, and publishes nothing.
    private func load() async {
        #if DEBUG
            if let sheetDetailPage {
                content = sheetDetailPage
                return
            }
        #endif
        let loaded = await model.detailContent(ref)
        guard !Task.isCancelled else { return }
        content = loaded
    }

    private func choosePlaylist(_ trackIDs: [Int64]) {
        addToPlaylistTarget = AddToPlaylistTarget(trackIDs: trackIDs)
    }
}
