import AppKit
import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Songs list (S10.8 Library PR-D — custom column-customizable list replacing the Table)

/// The Twin Panels song list: a horizontally-scrolling, column-customizable list of `SongRow`.
/// Default = the clean 5-column header-less view (`png/02`/`03`); customizing (via the header's
/// Columns pill) reveals the glass column-header row (`png/06`-`08`) and, when the columns overflow
/// the card, a horizontal scroll. Replaces the SwiftUI `Table` (which can't draw the mock's tinted
/// header-less rows + the playing-row equalizer). Selection lives HERE, in the `ListSelection` kit
/// (S10.8 E1): click / ⇧ / ⌘ click, ↑/↓ and ⇧↑/⇧↓, Home / End, Page Up / Down, ⌘A, Esc and
/// type-to-select; double-click / Return play; the context menu acts on the selection.
///
/// The `@AppStorage` column config is SHARED with `SongsHeader`'s Columns pill (same key) — the pill
/// toggles/reorders, this view renders + click-sorts. Sort writes the SAME `model.sortOrder` /
/// `applySortOrder` the old Table header-clicks used.
///
/// PR-D.2 (next sub-step): pin the frozen #+Title on horizontal scroll + drag-a-header reorder.
struct SongsListView: View {
    typealias RowID = LibraryTrackDisplay.ID

    /// The Songs card's one focus value (`SongsView` owns it, K1): the list holds key focus while it
    /// is `.content` — where Esc in the Filter pill sends it.
    let focus: FocusState<CardFocus?>.Binding

    @Environment(LibraryBrowseModel.self) private var model
    @Environment(AudioViewModel.self) private var viewModel
    @AppStorage("songs.columns.v2") private var columnConfig = SongColumnConfig.default

    @State private var selection = ListSelection<RowID>()
    @State private var infoTarget: LibraryTrackDisplay?
    @State private var addToPlaylistTarget: AddToPlaylistTarget?
    /// The row area's scroll position: the KEYBOARD sets it, to keep the cursor in view (A3) — never
    /// a click, which must not move a row out from under a double-click.
    @State private var rowScroll = ScrollPosition()
    /// The row area's visible span, for the keys alone (`ListVisibleSpan`).
    @State private var visibleSpan = ListVisibleSpan()
    /// Draw the cursor ring only while the user navigates by keyboard (A-review).
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    #if DEBUG
        /// Picture-sheet renderer only (`Debug/SheetFixture.swift`): rows its fixture draws as selected.
        @Environment(\.sheetSongSelection) private var sheetSongSelection
        /// `make songs-perf` only (`Debug/SongsPerfRun.swift`): counts passes and row builds, presses keys.
        @Environment(\.songsListProbe) private var probe
    #endif

    /// Inter-column gap, the row's own horizontal padding (both sides), and the row AREA's inset
    /// from the card edge (each side) — the chrome the layout math must budget so Title fills
    /// exactly / overflow triggers correctly.
    private static let columnSpacing: CGFloat = 14
    private static let rowHorizontalPadding: CGFloat = 24
    /// The guide's row area is a scroll view with "6×12 padding": 6 above/below, 12 at each side,
    /// and NO gap between rows (48pt rows at a 48pt pitch, png/02). The first cut read the 6 as
    /// inter-row spacing and dropped the 12 — rows sat 6pt apart (about one row in nine lost)
    /// and ran edge to edge, so a playing/selected row's fill touched the card border. The card's
    /// row-area token (`LayoutMetrics`), shared with the grids and a playlist's rows.
    private static let listVerticalInset = DesignSystem.LayoutMetrics.cardRowAreaInsetV
    private static let listHorizontalInset = DesignSystem.LayoutMetrics.cardRowAreaInsetH
    /// Everything that is not a column: gaps + row padding + the row area's side insets.
    private static func chromeWidth(columnCount: Int) -> CGFloat {
        columnSpacing * CGFloat(max(columnCount - 1, 0)) + rowHorizontalPadding + 2 * listHorizontalInset
    }

    var body: some View {
        GeometryReader { geo in
            let columns = orderedVisibleColumns
            let titleWidth = resolvedTitleWidth(columns: columns, available: geo.size.width)
            let pass = rowPass(columns: columns, titleWidth: titleWidth)
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    if columnConfig.isCustomized {
                        columnHeaderRow(columns: columns, titleWidth: titleWidth)
                    }
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.visibleSongs.enumerated()), id: \.element.id) { index, track in
                                row(track, number: index + 1, pass: pass)
                            }
                        }
                        .padding(.vertical, Self.listVerticalInset)
                        .padding(.horizontal, Self.listHorizontalInset)
                    }
                    // The VERTICAL scroll only, so a key can never yank the horizontal column
                    // scroll back to the leading edge.
                    .scrollPosition($rowScroll)
                    .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, visible in
                        visibleSpan.rect = visible
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(width: contentWidth(columns: columns, titleWidth: titleWidth),
                       height: geo.size.height, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .dynamicTypeSize(.small ... .xxLarge)
        // The full keyboard set on the selection kit (SEL-01…08), shared with the detail pages; Return
        // plays the cursor row alone (decision 11: on Songs, just that song).
        .modifier(ListSelectionKeyboard(selection: $selection, rows: model.visibleSongs, title: \.title,
                                        focus: focus, ringVisible: showsRing, pageRows: { _ in rowsPerPage },
                                        revealCursor: revealCursor, activate: playRow))
        .sheet(item: $addToPlaylistTarget) { target in
            PlaylistPickerSheet(trackIDs: target.trackIDs)
        }
        .popover(item: $infoTarget, arrowEdge: .trailing) { track in
            TrackInfoCard(file: AudioFile(track))
        }
        #if DEBUG
        // Seed the anchor too, so the fixture's selection is a real cursor state (the first seeded
        // row in visible order — never the Set's arbitrary `first`). A no-op in a normal run.
        .onAppear {
            probe?.press = { key in
                _ = navigate(key: key, extend: false)
                return selection.cursor.flatMap { id in model.visibleSongs.firstIndex { $0.id == id } }.map { $0 + 1 }
            }
            guard !sheetSongSelection.isEmpty else { return }
            selection = ListSelection(selecting: sheetSongSelection, in: rowIDs)
        }
        // Picture-sheet ring variant: focus, so the ring marks the seeded anchor.
        .sheetFocusSeed(.songs) { focus.wrappedValue = .content }
        #endif
    }

    // MARK: Column layout

    private var orderedVisibleColumns: [SongColumn] {
        columnConfig.frozen + columnConfig.scrollingColumns
    }

    /// Title fills leftover width when the set fits, else clamps to `titleMinWidth` (→ horizontal
    /// scroll). Budgets the fixed columns + inter-column spacing + row padding (the addendum).
    private func resolvedTitleWidth(columns: [SongColumn], available: CGFloat) -> CGFloat {
        let fixed = columns.filter { $0 != .title }.reduce(CGFloat.zero) { $0 + ($1.width ?? 0) }
        return max(SongColumn.titleMinWidth, available - fixed - Self.chromeWidth(columnCount: columns.count))
    }

    private func contentWidth(columns: [SongColumn], titleWidth: CGFloat) -> CGFloat {
        let fixed = columns.filter { $0 != .title }.reduce(CGFloat.zero) { $0 + ($1.width ?? 0) }
        return fixed + titleWidth + Self.chromeWidth(columnCount: columns.count)
    }

    // MARK: Glass column-header row (`png/08`)

    private func columnHeaderRow(columns: [SongColumn], titleWidth: CGFloat) -> some View {
        HStack(spacing: Self.columnSpacing) {
            ForEach(columns) { column in
                headerCell(column)
                    .frame(width: column == .title ? titleWidth : (column.width ?? SongColumn.titleMinWidth),
                           alignment: column == .index ? .center
                               : (column.isTrailing ? .trailing : .leading))
            }
        }
        // The row's own 12pt padding + the row area's side inset: header cells sit exactly over
        // the columns they label. The hairline still spans the full card width.
        .padding(.horizontal, Self.rowHorizontalPadding / 2 + Self.listHorizontalInset)
        .frame(height: 30)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private func headerCell(_ column: SongColumn) -> some View {
        let active = isActiveSort(column)
        // `headerLabel`, in the mock's own capitalisation (png/07-08 read "Title ↑ · Artist ·
        // Album"): the first cut upper-cased the full menu label, which is ~25% wider and
        // truncated the narrow numeric columns ("TRA…" for Track #). SLOT-04 holds every
        // header (+ its sort arrow) to its column width; the scale factor is only the net for
        // large Dynamic Type sizes, where the fixed widths do not grow.
        let label = HStack(spacing: SongColumn.headerArrowSpacing) {
            if column != .index {
                Text(column.headerLabel)
            }
            if active {
                Image(systemName: currentAscending ? "arrow.up" : "arrow.down")
                    .font(.system(size: SongColumn.headerArrowSize, weight: .bold))
                    .accessibilityHidden(true)
            }
        }
        .font(DesignSystem.Font.micro)
        .fontWeight(.heavy)
        .tracking(SongColumn.headerTracking)
        .foregroundStyle(active ? DesignSystem.Color.accentText : DesignSystem.Color.labelSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)

        if column.isSortable {
            Button { applySort(column) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel(column.label) // the full name, not the compact header
        } else {
            label.accessibilityLabel(column.label)
        }
    }

    // MARK: Rows

    /// What every row of one list pass shares, read ONCE per pass: a row does only O(1) work of its
    /// own — the list may build thousands of them (the S10.8 End-key hang).
    private struct RowPass {
        let columns: [SongColumn]
        let titleWidth: CGFloat
        /// The ring row (nil: no ring) and the playing row.
        let cursorID: RowID?
        let nowPlayingID: RowID?
        let isPlaybackActive: Bool
    }

    /// This list pass's `RowPass` — in the perf run (`make songs-perf`), also one counted pass.
    private func rowPass(columns: [SongColumn], titleWidth: CGFloat) -> RowPass {
        #if DEBUG
            probe?.countListPass()
        #endif
        return RowPass(columns: columns, titleWidth: titleWidth, cursorID: ringCursorID,
                       nowPlayingID: viewModel.playingTrackID, isPlaybackActive: viewModel.isPlaying)
    }

    private func row(_ track: LibraryTrackDisplay, number: Int, pass: RowPass) -> some View {
        #if DEBUG
            probe?.countRowBuild(number: number)
        #endif
        let isNowPlaying = track.id == pass.nowPlayingID
        return Button {
            handleClick(track)
        } label: {
            SongRow(track: track, number: number, columns: pass.columns, titleWidth: pass.titleWidth,
                    isNowPlaying: isNowPlaying,
                    isPlaybackActive: pass.isPlaybackActive,
                    isSelected: selection.contains(track.id),
                    isKeyboardCursor: track.id == pass.cursorID)
        }
        .buttonStyle(.plain)
        // Not a focus stop of its own: the LIST is the one Tab stop and the cursor ring its cue
        // (as `BrowseTile` and the facet rows). Clicks, the menu and VoiceOver are unaffected.
        .focusable(false)
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.playTrackNextNow(track) })
        .contextMenu {
            LibrarySongMenu(clicked: track, actsOnSelection: selection.menuActsOnSelection(clicked: track.id),
                            selectedTracks: selectedTracks, playClicked: { model.playTrackNextNow(track) },
                            showInfo: { infoTarget = $0 }, choosePlaylist: choosePlaylist)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SongsAccessibility.rowLabel(for: track))
        .accessibilityValue(rowAccessibilityValue(for: track, isNowPlaying: isNowPlaying))
        .accessibilityAddTraits(selection.contains(track.id) ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.playTrackNextNow(track) }
        .accessibilityAction(named: Text("Play Next")) { model.playNext([track]) }
        .accessibilityAction(named: Text("Add to Queue")) { model.append([track]) }
        .accessibilityAction(named: Text("Info")) { infoTarget = track }
    }

    /// The row's spoken value + a "Now playing" suffix for the current track — the equalizer is the
    /// only VISUAL now-playing cue, which VoiceOver can't see.
    private func rowAccessibilityValue(for track: LibraryTrackDisplay, isNowPlaying: Bool) -> String {
        let base = SongsAccessibility.rowValue(for: track)
        guard isNowPlaying else { return base }
        return base.isEmpty ? "Now playing" : base + ", Now playing"
    }

    // MARK: Sort (shared model source of truth)

    private var currentAscending: Bool {
        model.sortOrder.first?.order == .forward
    }

    private func isActiveSort(_ column: SongColumn) -> Bool {
        guard let forward = column.comparator(.forward) else { return false }
        return model.sortOrder.first?.keyPath == forward.keyPath
    }

    private func applySort(_ column: SongColumn) {
        guard let probe = column.comparator(.forward) else { return }
        let order: SortOrder
        if model.sortOrder.first?.keyPath == probe.keyPath {
            order = currentAscending ? .reverse : .forward
        } else {
            order = column.defaultOrder
        }
        guard let comparator = column.comparator(order) else { return }
        model.sortOrder = [comparator]
        model.applySortOrder([comparator])
        if let text = SongsAccessibility.sortAnnouncement(for: [comparator]) {
            AccessibilityNotification.Announcement(text).post()
        }
    }

    // MARK: Play + context (mirror the former SongsTable)

    /// The selected tracks in display order, without filter-hidden ones — resolved when a menu item is
    /// CHOSEN: an O(N) walk, so never while the menu is built (it is built with every row).
    private func selectedTracks() -> [LibraryTrackDisplay] {
        SongsRowResolver.orderedSelection(in: model.visibleSongs, selection: selection.ids)
    }

    /// "Add to Playlist…" from a row's menu: the searchable picker, for these songs.
    private func choosePlaylist(_ trackIDs: [Int64]) {
        addToPlaylistTarget = AddToPlaylistTarget(trackIDs: trackIDs)
    }
}

// MARK: - Selection + keyboard

/// Same-file extension (type-body length): reaches the list's private selection state. The keys
/// themselves are `ListSelectionKeyboard`'s; this is what only Songs knows.
private extension SongsListView {
    /// Page Up / Down move a screenful less one row, so the row the cursor left stays in view.
    var rowsPerPage: Int {
        max(Int((visibleSpan.rect.height - 2 * Self.listVerticalInset) / LibraryRowSize.regular.pitch) - 1, 1)
    }

    /// Scrolls the cursor row into view — as little as needed, none when it is already in view — by
    /// arithmetic on the fixed row height (`FixedRowReveal`). Scrolling to the row's ID made the lazy
    /// stack build every row up to it, and keep them: End over 10,000 songs built them all, and every
    /// later key rebuilt them all (the S10.8 End-key hang).
    func revealCursor() {
        guard let cursor = selection.cursor,
              let index = model.visibleSongs.firstIndex(where: { $0.id == cursor }),
              let offset = FixedRowReveal.offset(revealing: index, rowHeight: LibraryRowSize.regular.pitch,
                                                 inset: Self.listVerticalInset,
                                                 visibleTop: visibleSpan.rect.minY,
                                                 visibleHeight: visibleSpan.rect.height)
        else { return }
        rowScroll.scrollTo(y: offset)
    }

    /// The visible rows' ids in display order (filtered, sorted) — what every selection verb acts on.
    var rowIDs: some BidirectionalCollection<RowID> {
        model.visibleSongs.lazy.map(\.id)
    }

    /// The ONE keyboard cursor (A3, A-review): the ring row, the row the arrow and Page keys move
    /// from and the row Return plays — resolved by the selection kit over the visible rows.
    var keyboardCursor: ListKeyboardCursor<RowID>? {
        selection.keyboardCursor(in: rowIDs)
    }

    /// The ring is drawn while the list holds key focus AND the user navigates by keyboard.
    var showsRing: Bool {
        focus.wrappedValue == .content && showsKeyboardFocus
    }

    /// The row wearing the focus ring, or nil (no ring).
    var ringCursorID: RowID? {
        showsRing ? keyboardCursor?.id : nil
    }

    func handleClick(_ track: LibraryTrackDisplay) {
        focus.wrappedValue = .content
        selection.click(track.id, modifiers: NSEvent.modifierFlags, in: rowIDs)
    }

    #if DEBUG
        /// The perf run's key press (`make songs-perf`): the move a key makes, then the cursor into
        /// view — the path `ListSelectionKeyboard` takes for a real key. False when it moves nothing.
        func navigate(key: KeyEquivalent, extend: Bool) -> Bool {
            guard selection.move(key: key, extend: extend, in: rowIDs, pageRows: { _ in rowsPerPage })
            else { return false }
            revealCursor()
            return true
        }
    #endif

    /// Return: the cursor row plays alone (decision 11).
    func playRow(_ id: RowID) {
        guard let track = model.visibleSongs.first(where: { $0.id == id }) else { return }
        model.playTrackNextNow(track)
    }
}
