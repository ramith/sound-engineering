import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Detail page (S10.8 E2/E3 — the album, artist and genre pages)

/// An album, artist or genre page, on the Library's one card (mounted by `LibraryTabView`, D1 — the
/// page paints no card or background of its own): the header (`LibraryDetailHeader`) over the songs
/// (`DetailTrackList`), or "No Songs". One view for the three pages — they differ only in their
/// content (`LibraryBrowseModel.detailContent`).
///
/// It loads when it opens and again on every library change (`libraryRevision`, once per scan pass),
/// so a page stays true while a scan runs (review 13, 14, 19):
/// - the header's chrome draws at once; the content fills it when the first read lands;
/// - a reload that found the same page publishes nothing; one that found the page's album, artist or
///   genre gone closes the page; one that failed keeps what the page shows;
/// - the list keeps its selection (by id, less the rows that left) and its scroll across reloads —
///   and across a reload that briefly finds no songs: it keeps its last rows, hidden under "No
///   Songs", until songs come back;
/// - the list takes key focus once, when the page first has songs.
/// It hosts the one "Add to Playlist…" picker its header and rows share.
struct LibraryDetailPage: View {
    let ref: LibraryBrowseModel.FacetRef

    @Environment(LibraryBrowseModel.self) private var model
    @Environment(LibraryModel.self) private var library
    /// What the page shows; nil until the first read lands.
    @State private var content: LibraryDetailContent?
    /// The last layout that had songs — the list's, kept while a reload finds none.
    @State private var listLayout: DetailTrackLayout<LibraryTrackDisplay>?
    /// The list has taken key focus on this page (once, when the page first has songs).
    @State private var listTookFocus = false
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
            LibraryDetailHeader(ref: ref, content: content, choosePlaylist: choosePlaylist)
            ZStack {
                if let listLayout {
                    DetailTrackList(layout: listLayout, isShown: !showsNoSongs, albumArtist: content?.subtitle,
                                    focus: $focus, tookFocus: $listTookFocus, choosePlaylist: choosePlaylist)
                }
                if showsNoSongs {
                    // A reachable page whose songs all left the library (e.g. after a rescan).
                    ContentUnavailableView("No Songs", systemImage: "music.note")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Keyed on the revision alone: the page is one `ref` for its whole life — the route view gives
        // each page its own identity (`.id(route)`), so another page is a new view, not a new ref.
        .task(id: library.libraryRevision) { await load() }
        .sheet(item: $addToPlaylistTarget) { target in
            PlaylistPickerSheet(trackIDs: target.trackIDs)
        }
    }

    /// The page has loaded and has no songs.
    private var showsNoSongs: Bool {
        content?.layout.rows.isEmpty == true
    }

    /// Reads the page; a newer load (the next library change) wins — the task it superseded was
    /// cancelled while its read ran, and publishes nothing.
    private func load() async {
        #if DEBUG
            if let sheetDetailPage {
                publish(sheetDetailPage)
                return
            }
        #endif
        let loaded = await model.detailContent(ref)
        guard !Task.isCancelled else { return }
        switch loaded {
        case let .page(page): publish(page)
        case .gone: close()
        case .failed: break // a failed read never blanks the page: it keeps what it shows
        }
    }

    /// Shows `page` — unless it is what the page already shows. The list takes its rows only when
    /// there are some, so a reload that briefly finds none keeps its selection and scroll.
    private func publish(_ page: LibraryDetailContent) {
        guard page != content else { return }
        content = page
        if !page.layout.rows.isEmpty {
            listLayout = page.layout
        }
    }

    /// The page's album, artist or genre left the library: back to the grid it was opened from —
    /// if the page is still the one on top.
    private func close() {
        if model.path.last == ref.route {
            model.path.removeLast()
        }
    }

    private func choosePlaylist(_ trackIDs: [Int64]) {
        addToPlaylistTarget = AddToPlaylistTarget(trackIDs: trackIDs)
    }
}
