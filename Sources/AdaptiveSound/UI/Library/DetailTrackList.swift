import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Detail page song list (S10.8 E2/E3 — one list for the album, artist and genre pages)

/// The song list of an album, artist or genre page, on the selection kit (`ListSelection`) like
/// Songs, and sharing Songs' row behaviour (`SongRowInteraction`: click, double-click, drag to a
/// playlist, the song menu, VoiceOver's actions) and keyboard (`ListSelectionKeyboard`, SEL-01…08,
/// with ⌘↩ / ⇧⌘↩ / ⌘I for the menu's verbs). What a page adds is its play context (decision 11): a
/// double-click, Return or Play on a row plays the PAGE, in the order shown, from that song on
/// (`DetailTrackLayout.playFromRow`).
///
/// The selection is kept by id, so it survives the page reloading under it (a library change).
struct DetailTrackList: View {
    typealias RowID = LibraryTrackDisplay.ID

    let layout: DetailTrackLayout<LibraryTrackDisplay>
    /// The list is on screen. False while a reload finds no songs: the list keeps its rows, its
    /// selection and its scroll, hidden — out of reach of the pointer, the keys and VoiceOver — under
    /// the page's "No Songs" until songs come back (review 13).
    let isShown: Bool
    /// An album page's album artist: a song by anyone else names its artist after its title
    /// (decision 12's compilations). Nil on the other pages.
    let albumArtist: String?
    /// The page's one focus value: the list is its `.content` stop.
    let focus: FocusState<CardFocus?>.Binding
    /// "Add to Playlist…": the page's searchable picker, for these songs.
    let choosePlaylist: ([Int64]) -> Void

    @Environment(LibraryBrowseModel.self) private var model
    @Environment(AudioViewModel.self) private var viewModel
    /// Draw the cursor ring only while the user navigates by keyboard (A-review).
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    /// The list has taken key focus on this page: it does once, when it first appears. The list's own
    /// state is the page's: once the page has songs it keeps its list for its whole life (a reload
    /// that finds none keeps the rows), so this list is never made again for the same page.
    @State private var tookFocus = false
    @State private var selection = ListSelection<RowID>()
    @State private var infoTarget: LibraryTrackDisplay?
    /// The row area's scroll position: the KEYBOARD sets it, to keep the cursor in view (A3) — never a
    /// click, which must not move a row out from under a double-click.
    @State private var rowScroll = ScrollPosition()
    /// The row area's visible span, for the keys alone.
    @State private var visibleSpan = ListVisibleSpan()
    #if DEBUG
        /// Picture-sheet renderer only (`Debug/SheetFixture.swift`): rows its fixture draws as selected.
        @Environment(\.sheetSongSelection) private var sheetSongSelection
    #endif

    /// The Library card's row area insets (`LayoutMetrics`), shared with Songs, the grids and a
    /// playlist's rows.
    private static let verticalInset = DesignSystem.LayoutMetrics.cardRowAreaInsetV
    private static let horizontalInset = DesignSystem.LayoutMetrics.cardRowAreaInsetH

    var body: some View {
        let pass = rowPass
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(layout.items) { item in
                    switch item {
                    case let .header(_, title, year): DetailSectionHeader(title: title, year: year)
                    case let .discHeader(_, disc): DetailDiscHeader(disc: disc)
                    case let .row(track, number, disc): row(track, number: number, disc: disc, pass: pass)
                    }
                }
            }
            .padding(.vertical, Self.verticalInset)
            .padding(.horizontal, Self.horizontalInset)
        }
        .scrollPosition($rowScroll)
        .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, visible in
            visibleSpan.rect = visible
        }
        .scrollContentBackground(.hidden)
        .dynamicTypeSize(.small ... .xxLarge)
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(isShown)
        .accessibilityHidden(!isShown)
        // Hidden, it has no rows to act on — and so is no focus stop and takes no key.
        .modifier(ListSelectionKeyboard(selection: $selection, rows: isShown ? layout.rows : [], title: \.title,
                                        focus: focus,
                                        ringVisible: showsRing, pageRows: pageRows,
                                        revealCursor: revealCursor, activate: play(from:),
                                        playNext: model.playNext, addToQueue: model.append,
                                        showInfo: { infoTarget = $0 }))
        .popover(item: $infoTarget, arrowEdge: .trailing) { track in
            TrackInfoCard(file: AudioFile(track))
        }
        // The page reloaded under the list: only the selected rows it still shows stay selected — no
        // ghost ids for a menu, a ⇧-range or VoiceOver's count to trip on (review 12, break-it 10).
        .onChange(of: layout) { _, reloaded in
            selection.keepOnly(reloaded.rows.lazy.map(\.id))
        }
        // The page opens from a grid that held key focus (a click on a tile focuses it, as Return
        // does), so the keys go on here: ↓ claims the first song — once per page, when it first has
        // songs (review 13). The write waits a turn, as the grid's own restore does — the list may
        // not be a focus target on its first appearance.
        .onAppear {
            guard !tookFocus else { return }
            tookFocus = true
            Task { @MainActor in
                focus.wrappedValue = .content
            }
        }

        #if DEBUG
        .onAppear {
            guard !sheetSongSelection.isEmpty else { return }
            selection = ListSelection(selecting: sheetSongSelection, in: layout.rows.map(\.id))
        }
        #endif
    }

    // MARK: Rows

    /// What every row of one list pass shares, read once per pass, so a row does O(1) work.
    private struct RowPass {
        /// The ring row (nil: no ring) and the current song's row.
        let cursorID: RowID?
        let nowPlayingID: RowID?
        let isPlaybackActive: Bool
        /// The rows' shared behaviour (`SongRowInteraction`): a row's own play is the page from it on.
        let interaction: SongRowContext
    }

    private var rowPass: RowPass {
        let interaction = SongRowContext(model: model, rows: layout.rows, selection: $selection, focus: focus,
                                         play: { play(from: $0.id) }, showInfo: { infoTarget = $0 },
                                         choosePlaylist: choosePlaylist)
        return RowPass(cursorID: ringCursorID, nowPlayingID: viewModel.playingTrackID,
                       isPlaybackActive: viewModel.isPlaying, interaction: interaction)
    }

    private func row(_ track: LibraryTrackDisplay, number: Int?, disc: Int?, pass: RowPass) -> some View {
        let isNowPlaying = track.id == pass.nowPlayingID
        let artist = inlineArtist(track)
        let secondary = secondaryLine(track)
        return DetailTrackRow(track: track, size: rowSize, showsNumberColumn: layout.arrangement != .flat,
                              number: number, inlineArtist: artist, secondary: secondary,
                              isNowPlaying: isNowPlaying, isPlaybackActive: pass.isPlaybackActive,
                              isSelected: selection.contains(track.id), isKeyboardCursor: track.id == pass.cursorID)
            .songRowInteraction(
                track, in: pass.interaction,
                label: DetailTrackRow.accessibilityLabel(for: track, inlineArtist: artist, secondary: secondary),
                value: DetailTrackRow.accessibilityValue(disc: disc, number: number, isNowPlaying: isNowPlaying)
            )
    }

    /// On an album's page, the artist of a song that is not the album artist's — a compilation's
    /// rows, a guest's song — to show after its title. Nil where the page's header already names them.
    private func inlineArtist(_ track: LibraryTrackDisplay) -> String? {
        guard layout.arrangement == .album, let albumArtist, !track.artistName.isEmpty,
              track.artistName.localizedCaseInsensitiveCompare(albumArtist) != .orderedSame else { return nil }
        return track.artistName
    }

    /// The line under a title: on a genre page (one flat list of many artists' songs), "Artist ·
    /// Album" — the Songs convention; none on an album or artist page, whose header (or album header)
    /// already says both.
    private func secondaryLine(_ track: LibraryTrackDisplay) -> String {
        guard layout.arrangement == .flat else { return "" }
        return [track.artistDisplayName, track.albumName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Play, selection and keys

    /// Decision 11: the page, in the order shown, from this song on.
    private func play(from id: RowID) {
        guard let request = layout.playFromRow(id) else { return }
        model.play(request.tracks, startAt: request.startIndex)
    }

    /// The ring is drawn while the list holds key focus AND the user navigates by keyboard.
    private var showsRing: Bool {
        focus.wrappedValue == .content && showsKeyboardFocus
    }

    /// The row wearing the focus ring, or nil (no ring).
    private var ringCursorID: RowID? {
        showsRing ? selection.keyboardCursor(in: layout.rows.lazy.map(\.id))?.id : nil
    }

    /// The rows' size: single-line rows (an album's, an artist's) at the queue and playlist rows'
    /// 36 pt pitch; a genre's two-line rows at Songs' 48 pt. One size per page, so the pitch is fixed.
    private var rowSize: LibraryRowSize {
        layout.arrangement == .flat ? .regular : .compact
    }

    /// The list's fixed heights: its one row pitch, and the album and disc headers'.
    private var metrics: DetailListMetrics {
        DetailListMetrics(rowHeight: rowSize.pitch, albumHeaderHeight: DetailSectionHeader.height,
                          discHeaderHeight: DetailDiscHeader.height)
    }

    /// Page Up / Down move a screenful less one row, so the row the cursor left stays in view —
    /// counted from the cursor's row by what fits (`DetailTrackLayout.pageRows`), so the album and
    /// disc headers between the rows take their share of the screen.
    private func pageRows(_ direction: Int) -> Int {
        guard let cursor = selection.keyboardCursor(in: layout.rows.lazy.map(\.id))?.id,
              let index = layout.index(of: cursor) else { return 1 }
        return layout.pageRows(from: index, direction: direction,
                               viewportHeight: visibleSpan.rect.height - 2 * Self.verticalInset, metrics: metrics)
    }

    /// Scrolls the cursor row into view — as little as needed, with the album or disc header above
    /// it when it is their first song — by arithmetic on the page's fixed row pitch and header heights
    /// (`FixedRowReveal`), never by the lazy stack's id lookup, which builds every row up to it.
    private func revealCursor() {
        guard let cursor = selection.cursor, let index = layout.index(of: cursor) else { return }
        let span = layout.span(ofRow: index, metrics: metrics)
        guard let offset = FixedRowReveal.offset(revealingSpanAt: span.top, height: span.height,
                                                 inset: Self.verticalInset, visibleTop: visibleSpan.rect.minY,
                                                 visibleHeight: visibleSpan.rect.height)
        else { return }
        rowScroll.scrollTo(y: offset)
    }
}
