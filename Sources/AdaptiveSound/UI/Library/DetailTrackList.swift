import AppKit
import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Detail page song list (S10.8 E2/E3 — one list for the album, artist and genre pages)

/// The song list of an album, artist or genre page, on the selection kit (`ListSelection`) like
/// Songs: plain button rows in a lazy stack (a `List(selection:)` races a row's double-click and drops
/// clicks on macOS), the full keyboard set (`ListSelectionKeyboard`, SEL-01…08), and the song menu,
/// VoiceOver actions and Info popover Songs has. What a page adds is its play context (decision 11):
/// a double-click, Return or Play on a row plays the PAGE, in the order shown, from that song on
/// (`DetailTrackLayout.playFromRow`). A row drags onto a sidebar playlist (a reference-add by id).
///
/// The selection is kept by id, so it survives the page reloading under it (a library change).
struct DetailTrackList: View {
    typealias RowID = LibraryTrackDisplay.ID

    let layout: DetailTrackLayout<LibraryTrackDisplay>
    /// The page's one focus value: the list is its `.content` stop.
    let focus: FocusState<CardFocus?>.Binding
    /// "Add to Playlist…": the page's searchable picker, for these songs.
    let choosePlaylist: ([Int64]) -> Void

    @Environment(LibraryBrowseModel.self) private var model
    @Environment(AudioViewModel.self) private var viewModel
    /// Draw the cursor ring only while the user navigates by keyboard (A-review).
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
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
        let pass = RowPass(cursorID: ringCursorID, nowPlayingID: viewModel.playingTrackID,
                           isPlaybackActive: viewModel.isPlaying)
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(layout.items) { item in
                    switch item {
                    case let .header(_, title, year): DetailSectionHeader(title: title, year: year)
                    case let .row(track, number): row(track, number: number, pass: pass)
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
        .modifier(ListSelectionKeyboard(selection: $selection, rows: layout.rows, title: \.title, focus: focus,
                                        ringVisible: showsRing, pageRows: { rowsPerPage },
                                        revealCursor: revealCursor, activate: play(from:)))
        .popover(item: $infoTarget, arrowEdge: .trailing) { track in
            TrackInfoCard(file: AudioFile(track))
        }
        // The page opens from a grid that held key focus (a click on a tile focuses it, as Return
        // does), so the keys go on here: ↓ claims the first song. The write waits a turn, as the
        // grid's own restore does — the list may not be a focus target on its first appearance.
        .onAppear {
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
        /// The ring row (nil: no ring) and the playing row.
        let cursorID: RowID?
        let nowPlayingID: RowID?
        let isPlaybackActive: Bool
    }

    private func row(_ track: LibraryTrackDisplay, number: Int?, pass: RowPass) -> some View {
        let isNowPlaying = track.id == pass.nowPlayingID
        let isSelected = selection.contains(track.id)
        let secondary = secondaryLine(track)
        return Button {
            handleClick(track)
        } label: {
            DetailTrackRow(track: track, size: rowSize, showsNumberColumn: layout.arrangement != .flat,
                           number: number, secondary: secondary, isNowPlaying: isNowPlaying,
                           isPlaybackActive: pass.isPlaybackActive, isSelected: isSelected,
                           isKeyboardCursor: track.id == pass.cursorID)
        }
        .buttonStyle(.plain)
        // Not a focus stop of its own: the LIST is the one Tab stop and the cursor ring its cue.
        .focusable(false)
        // Drag a song onto a sidebar playlist (US-PLIST-03) — a reference-add by id, never a file move.
        .draggable(LibraryTrackDragItem(trackID: track.id))
        .simultaneousGesture(TapGesture(count: 2).onEnded { play(from: track.id) })
        .contextMenu {
            LibrarySongMenu(clicked: track, actsOnSelection: selection.menuActsOnSelection(clicked: track.id),
                            selectedTracks: selectedTracks, playClicked: { play(from: track.id) },
                            showInfo: { infoTarget = $0 }, choosePlaylist: choosePlaylist)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DetailTrackRow.accessibilityLabel(for: track, secondary: secondary))
        .accessibilityValue(DetailTrackRow.accessibilityValue(number: number, isNowPlaying: isNowPlaying))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { play(from: track.id) }
        .accessibilityAction(named: Text("Play Next")) { model.playNext([track]) }
        .accessibilityAction(named: Text("Add to Queue")) { model.append([track]) }
        .accessibilityAction(named: Text("Info")) { infoTarget = track }
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

    /// The selected songs in display order — resolved when a menu item is CHOSEN, never while a row
    /// is built.
    private func selectedTracks() -> [LibraryTrackDisplay] {
        SongsRowResolver.orderedSelection(in: layout.rows, selection: selection.ids)
    }

    private func handleClick(_ track: LibraryTrackDisplay) {
        focus.wrappedValue = .content
        selection.click(track.id, modifiers: NSEvent.modifierFlags, in: layout.rows.lazy.map(\.id))
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

    /// Page Up / Down move a screenful less one row, so the row the cursor left stays in view.
    private var rowsPerPage: Int {
        max(Int((visibleSpan.rect.height - 2 * Self.verticalInset) / rowSize.pitch) - 1, 1)
    }

    /// Scrolls the cursor row into view — as little as needed, with its album header when it is the
    /// album's first song — by arithmetic on the page's fixed row pitch and header height
    /// (`FixedRowReveal`), never by the lazy stack's id lookup, which builds every row up to it.
    private func revealCursor() {
        guard let cursor = selection.cursor, let index = layout.index(of: cursor) else { return }
        let span = layout.span(ofRow: index, rowHeight: rowSize.pitch, headerHeight: DetailSectionHeader.height)
        guard let offset = FixedRowReveal.offset(revealingSpanAt: span.top, height: span.height,
                                                 inset: Self.verticalInset, visibleTop: visibleSpan.rect.minY,
                                                 visibleHeight: visibleSpan.rect.height)
        else { return }
        rowScroll.scrollTo(y: offset)
    }
}
