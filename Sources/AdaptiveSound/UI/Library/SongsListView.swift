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

    @Environment(LibraryBrowseModel.self) private var model
    @Environment(AudioViewModel.self) private var viewModel
    @AppStorage("songs.columns.v2") private var columnConfig = SongColumnConfig.default

    @State private var selection = ListSelection<RowID>()
    @State private var infoTarget: LibraryTrackDisplay?
    @State private var addToPlaylistTarget: AddToPlaylistTarget?
    /// Bumped by the KEYBOARD only (never a click — scrolling must not move a row out from under a
    /// double-click); the row area's `ScrollViewReader` observes it and scrolls the cursor into
    /// view (A3). A counter, like the queue's jump request, so every press re-fires.
    @State private var cursorScrollRequest = 0
    /// Rows Page Up / Down move: from the row area's measured height (`rowsPerPage(viewportHeight:)`).
    @State private var rowsPerPage = 1
    @FocusState private var listFocused: Bool
    /// Draw the cursor ring only while the user navigates by keyboard (A-review).
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    #if DEBUG
        /// Picture-sheet renderer only (`Debug/SheetFixture.swift`): rows its fixture draws as selected.
        @Environment(\.sheetSongSelection) private var sheetSongSelection
    #endif

    /// Inter-column gap, the row's own horizontal padding (both sides), and the row AREA's inset
    /// from the card edge (each side) — the chrome the layout math must budget so Title fills
    /// exactly / overflow triggers correctly.
    private static let columnSpacing: CGFloat = 14
    private static let rowHorizontalPadding: CGFloat = 24
    /// The guide's row area is a scroll view with "6×12 padding": 6 above/below, 12 at each side,
    /// and NO gap between rows (48pt rows at a 48pt pitch, png/02). The first cut read the 6 as
    /// inter-row spacing and dropped the 12 — rows sat 6pt apart (about one row in nine lost)
    /// and ran edge to edge, so a playing/selected row's fill touched the card border.
    private nonisolated static let listVerticalInset: CGFloat = 6
    private static let listHorizontalInset: CGFloat = 12
    /// Everything that is not a column: gaps + row padding + the row area's side insets.
    private static func chromeWidth(columnCount: Int) -> CGFloat {
        columnSpacing * CGFloat(max(columnCount - 1, 0)) + rowHorizontalPadding + 2 * listHorizontalInset
    }

    var body: some View {
        GeometryReader { geo in
            let columns = orderedVisibleColumns
            let titleWidth = resolvedTitleWidth(columns: columns, available: geo.size.width)
            let cursorID = ringCursorID
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    if columnConfig.isCustomized {
                        columnHeaderRow(columns: columns, titleWidth: titleWidth)
                    }
                    // The reader wraps ONLY the vertical scroll, so `scrollTo` can never yank the
                    // horizontal column scroll back to the leading edge.
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(model.visibleSongs.enumerated()), id: \.element.id) { index, track in
                                    row(track, number: index + 1, columns: columns, titleWidth: titleWidth,
                                        isKeyboardCursor: track.id == cursorID)
                                        .id(track.id) // the arrow keys' `scrollTo` target
                                }
                            }
                            .padding(.vertical, Self.listVerticalInset)
                            .padding(.horizontal, Self.listHorizontalInset)
                        }
                        // Keep the cursor on screen the queue's way: no anchor = scroll only as far
                        // as needed (none when the row is already visible), instantly.
                        .onChange(of: cursorScrollRequest) {
                            if let cursor = selection.cursor {
                                proxy.scrollTo(cursor)
                            }
                        }
                        .onGeometryChange(for: Int.self) { geometry in
                            Self.rowsPerPage(viewportHeight: geometry.size.height)
                        } action: { rowsPerPage = $0 }
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(width: contentWidth(columns: columns, titleWidth: titleWidth),
                       height: geo.size.height, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .dynamicTypeSize(.small ... .xxLarge)
        // An empty list (a filter matching nothing) has no cursor row — and so is no focus stop.
        .focusable(!model.visibleSongs.isEmpty)
        .focused($listFocused)
        // The system effect would outline the whole list; the cursor row's ring replaces it (A3).
        .focusEffectDisabled()
        .onKeyPress(keys: Self.navigationKeys) { navigate($0) }
        .onKeyPress(.return) { playCursorRow() }
        .onKeyPress(characters: Self.typeSelectCharacters, phases: .down) { typeSelect($0) }
        // ⌘A and Edit ▸ Select All: the standard `selectAll:` action, sent to the focused list.
        .onCommand(#selector(NSStandardKeyBindingResponding.selectAll(_:))) {
            selection.selectAll(in: rowIDs)
        }
        .onExitCommand { selection.clear() } // Esc — the macOS cancel command
        // VoiceOver hears a count change it cannot see: ⇧-arrows, ⌘A and Esc change only the tint.
        .onChange(of: selection.ids.count) { _, count in
            AccessibilityNotification.Announcement(SongsAccessibility.selectionAnnouncement(count: count)).post()
        }
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
            guard !sheetSongSelection.isEmpty else { return }
            selection = ListSelection(selecting: sheetSongSelection, in: rowIDs)
        }
        // Picture-sheet ring variant: focus, so the ring marks the seeded anchor.
        .sheetFocusSeed(.songs) { listFocused = true }
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

    private func row(_ track: LibraryTrackDisplay, number: Int,
                     columns: [SongColumn], titleWidth: CGFloat, isKeyboardCursor: Bool) -> some View {
        Button {
            handleClick(track)
        } label: {
            SongRow(track: track, number: number, columns: columns, titleWidth: titleWidth,
                    isNowPlaying: track.id == currentTrackID,
                    isPlaybackActive: viewModel.isPlaying,
                    isSelected: selection.contains(track.id),
                    isKeyboardCursor: isKeyboardCursor)
        }
        .buttonStyle(.plain)
        // Not a focus stop of its own: the LIST is the one Tab stop and the cursor ring its cue
        // (as `BrowseTile` and the facet rows). Clicks, the menu and VoiceOver are unaffected.
        .focusable(false)
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.playTrackNextNow(track) })
        .contextMenu { menuItems(for: contextIDs(clicked: track)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SongsAccessibility.rowLabel(for: track))
        .accessibilityValue(rowAccessibilityValue(for: track))
        .accessibilityAddTraits(selection.contains(track.id) ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.playTrackNextNow(track) }
        .accessibilityAction(named: Text("Play Next")) { model.playNext([track]) }
        .accessibilityAction(named: Text("Add to Queue")) { model.append([track]) }
        .accessibilityAction(named: Text("Info")) { infoTarget = track }
    }

    private var currentTrackID: Int64? {
        guard viewModel.isPlaying, let index = viewModel.selectedTrackIndex,
              index < viewModel.queue.count else { return nil }
        return viewModel.queue[index].file.trackID
    }

    /// The row's spoken value + a "Now playing" suffix for the current track — the equalizer is the
    /// only VISUAL now-playing cue, which VoiceOver can't see.
    private func rowAccessibilityValue(for track: LibraryTrackDisplay) -> String {
        let base = SongsAccessibility.rowValue(for: track)
        guard track.id == currentTrackID else { return base }
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

    private func contextIDs(clicked track: LibraryTrackDisplay) -> Set<RowID> {
        selection.contains(track.id) ? selection.ids : [track.id]
    }

    private func orderedTracks(for ids: Set<RowID>) -> [LibraryTrackDisplay] {
        SongsRowResolver.orderedSelection(in: model.visibleSongs, selection: ids)
    }

    @ViewBuilder
    private func menuItems(for ids: Set<RowID>) -> some View {
        if ids.count > 1 {
            let tracks = orderedTracks(for: ids)
            Button("Play") { model.play(tracks, startAt: 0) }
            Button("Play Next") { model.playNext(tracks) }
            Button("Add to Queue") { model.append(tracks) }
            Divider()
            addToPlaylistMenu(trackIDs: tracks.map(\.id))
            Divider()
            Button("Info", systemImage: "info.circle") { infoTarget = tracks.first }
        } else if let track = SongsRowResolver.primaryRow(in: model.visibleSongs, selection: ids) {
            Button("Play") { model.playTrackNextNow(track) }
            Button("Play Next") { model.playNext([track]) }
            Button("Add to Queue") { model.append([track]) }
            Divider()
            addToPlaylistMenu(trackIDs: [track.id])
            Divider()
            Button("Info", systemImage: "info.circle") { infoTarget = track }
        }
    }

    private func addToPlaylistMenu(trackIDs: [Int64]) -> some View {
        AddToPlaylistMenu(resolveTrackIDs: { trackIDs }, onChooseMore: { ids in
            addToPlaylistTarget = AddToPlaylistTarget(trackIDs: ids)
        })
    }
}

// MARK: - Selection + keyboard

/// Same-file extension (type-body length): reaches the list's private selection state.
private extension SongsListView {
    /// The keys `navigate` moves the cursor with.
    static let navigationKeys: Set<KeyEquivalent> = [.upArrow, .downArrow, .home, .end, .pageUp, .pageDown]

    /// Type-to-select keys: letters, digits, punctuation and symbols. Not Space — the app-wide play /
    /// pause key (§H) — so a search never starts or goes on with it, queue or no queue.
    static let typeSelectCharacters = CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols)

    /// Page Up / Down move a screenful less one row, so the row the cursor left stays in view.
    /// Nonisolated (with the two metrics it reads): `onGeometryChange` runs it off the main actor.
    nonisolated static func rowsPerPage(viewportHeight: CGFloat) -> Int {
        max(Int((viewportHeight - 2 * listVerticalInset) / SongRow.height) - 1, 1)
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
        listFocused && showsKeyboardFocus
    }

    /// The row wearing the focus ring, or nil (no ring).
    var ringCursorID: RowID? {
        showsRing ? keyboardCursor?.id : nil
    }

    func handleClick(_ track: LibraryTrackDisplay) {
        listFocused = true
        let flags = NSEvent.modifierFlags
        selection.click(track.id, extend: flags.contains(.shift), toggle: flags.contains(.command), in: rowIDs)
    }

    /// ↑/↓, Home / End, Page Up / Down — with ⇧, extending the range from the anchor. Asks the row
    /// area to scroll the cursor into view. A key that moves nothing bubbles, and so does one held
    /// with ⌘, ⌥ or ⌃ (`BrowseKeyboard`'s rule): those are the app's and the system's shortcuts,
    /// never a plain step.
    func navigate(_ press: KeyPress) -> KeyPress.Result {
        guard !press.isShortcut,
              let movement = movement(for: press.key),
              selection.move(movement, extend: press.modifiers.contains(.shift), in: rowIDs) != nil
        else { return .ignored }
        cursorScrollRequest &+= 1
        return .handled
    }

    func movement(for key: KeyEquivalent) -> ListSelection<RowID>.Movement? {
        switch key {
        case .upArrow: .step(-1)
        case .downArrow: .step(1)
        case .pageUp: .page(-rowsPerPage)
        case .pageDown: .page(rowsPerPage)
        case .home: .first
        case .end: .last
        default: nil
        }
    }

    /// Return: play the cursor row — the ring row, or the selected cursor row while the ring is
    /// hidden (`ListSelection.activate`, which claims a ring-only row first).
    func playCursorRow() -> KeyPress.Result {
        guard let id = selection.activate(in: rowIDs, ringVisible: showsRing),
              let track = model.visibleSongs.first(where: { $0.id == id }) else { return .ignored }
        model.playTrackNextNow(track)
        return .handled
    }

    /// Type-to-select over the displayed titles, in the current order — `BrowseKeyboard`'s rule: on
    /// the key-down only (a held key does not repeat into the search), and a key with ⌘, ⌥ or ⌃ is
    /// a shortcut, not typing. A key that matches nothing is still consumed, so it doesn't beep.
    func typeSelect(_ press: KeyPress) -> KeyPress.Result {
        guard !press.isShortcut else { return .ignored }
        if selection.typeSelect(press.characters, at: .now, in: model.visibleSongs, title: \.title) != nil {
            cursorScrollRequest &+= 1
        }
        return .handled
    }
}
