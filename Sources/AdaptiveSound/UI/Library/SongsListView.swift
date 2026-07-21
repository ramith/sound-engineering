import AppKit
import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Songs list (S10.8 Library PR-D — custom column-customizable list replacing the Table)

/// The Twin Panels song list: a horizontally-scrolling, column-customizable list of `SongRow`.
/// Default = the clean 5-column header-less view (`png/02`/`03`); customizing (via the header's
/// Columns pill) reveals the glass column-header row (`png/06`-`08`) and, when the columns overflow
/// the card, a horizontal scroll. Replaces the SwiftUI `Table` (which can't draw the mock's tinted
/// header-less rows + the playing-row equalizer). Selection lives HERE; ⌘/⇧ click multi-select +
/// ↑/↓ nav are rebuilt; double-click / Return play; the context menu mirrors the old table.
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

    @State private var selection = Set<RowID>()
    @State private var anchorID: RowID?
    @State private var infoTarget: LibraryTrackDisplay?
    @State private var addToPlaylistTarget: AddToPlaylistTarget?
    @FocusState private var listFocused: Bool

    /// Inter-column gap + the row's horizontal padding (both sides) — the row chrome the layout math
    /// must budget so Title fills exactly / overflow triggers correctly.
    private static let columnSpacing: CGFloat = 14
    private static let rowHorizontalPadding: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let columns = orderedVisibleColumns
            let titleWidth = resolvedTitleWidth(columns: columns, available: geo.size.width)
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    if columnConfig.isCustomized {
                        columnHeaderRow(columns: columns, titleWidth: titleWidth)
                    }
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(model.visibleSongs.enumerated()), id: \.element.id) { index, track in
                                row(track, number: index + 1, columns: columns, titleWidth: titleWidth)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(width: contentWidth(columns: columns, titleWidth: titleWidth),
                       height: geo.size.height, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .dynamicTypeSize(.small ... .xxLarge)
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.return) { playSelection() ? .handled : .ignored }
        .sheet(item: $addToPlaylistTarget) { target in
            PlaylistPickerSheet(trackIDs: target.trackIDs)
        }
        .popover(item: $infoTarget, arrowEdge: .trailing) { track in
            TrackInfoCard(file: AudioFile(track))
        }
    }

    // MARK: Column layout

    private var orderedVisibleColumns: [SongColumn] {
        columnConfig.frozen + columnConfig.scrollingColumns
    }

    /// Title fills leftover width when the set fits, else clamps to `titleMinWidth` (→ horizontal
    /// scroll). Budgets the fixed columns + inter-column spacing + row padding (the addendum).
    private func resolvedTitleWidth(columns: [SongColumn], available: CGFloat) -> CGFloat {
        let fixed = columns.filter { $0 != .title }.reduce(CGFloat.zero) { $0 + ($1.width ?? 0) }
        let chrome = Self.columnSpacing * CGFloat(max(columns.count - 1, 0)) + Self.rowHorizontalPadding
        return max(SongColumn.titleMinWidth, available - fixed - chrome)
    }

    private func contentWidth(columns: [SongColumn], titleWidth: CGFloat) -> CGFloat {
        let fixed = columns.filter { $0 != .title }.reduce(CGFloat.zero) { $0 + ($1.width ?? 0) }
        let chrome = Self.columnSpacing * CGFloat(max(columns.count - 1, 0)) + Self.rowHorizontalPadding
        return fixed + titleWidth + chrome
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
        .padding(.horizontal, 12)
        .frame(height: 30)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private func headerCell(_ column: SongColumn) -> some View {
        let sortable = column.comparator(.forward) != nil
        let active = isActiveSort(column)
        let label = HStack(spacing: 4) {
            if column != .index { Text(column.label) }
            if active {
                Image(systemName: currentAscending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .accessibilityHidden(true)
            }
        }
        .font(DesignSystem.Font.micro)
        .fontWeight(.heavy)
        .tracking(0.6)
        .textCase(.uppercase)
        .foregroundStyle(active ? DesignSystem.Color.accentText : DesignSystem.Color.labelSecondary)
        .lineLimit(1)

        if sortable {
            Button { applySort(column) } label: { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    // MARK: Rows

    private func row(_ track: LibraryTrackDisplay, number: Int,
                     columns: [SongColumn], titleWidth: CGFloat) -> some View {
        Button {
            handleClick(track)
        } label: {
            SongRow(track: track, number: number, columns: columns, titleWidth: titleWidth,
                    isNowPlaying: track.id == currentTrackID,
                    isPlaybackActive: viewModel.isPlaying,
                    isSelected: selection.contains(track.id))
        }
        .buttonStyle(.plain)
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

    // MARK: Selection

    private func handleClick(_ track: LibraryTrackDisplay) {
        listFocused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = anchorID {
            selectRange(from: anchor, to: track.id)
        } else if flags.contains(.command) {
            if selection.contains(track.id) { selection.remove(track.id) } else { selection.insert(track.id) }
            anchorID = track.id
        } else {
            selection = [track.id]
            anchorID = track.id
        }
    }

    private func selectRange(from start: RowID, to end: RowID) {
        let ids = model.visibleSongs.map(\.id)
        guard let i = ids.firstIndex(of: start), let j = ids.firstIndex(of: end) else {
            selection = [end]
            return
        }
        selection = Set(ids[min(i, j) ... max(i, j)])
    }

    private func moveSelection(by delta: Int) -> KeyPress.Result {
        let ids = model.visibleSongs.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let currentIndex = (anchorID ?? selection.first).flatMap { ids.firstIndex(of: $0) } ?? -1
        let next = currentIndex + delta
        guard next >= 0, next < ids.count else { return .ignored }
        selection = [ids[next]]
        anchorID = ids[next]
        return .handled
    }

    // MARK: Play + context (mirror the former SongsTable)

    @discardableResult
    private func playSelection() -> Bool {
        guard let track = SongsRowResolver.primaryRow(in: model.visibleSongs, selection: selection)
        else { return false }
        model.playTrackNextNow(track)
        return true
    }

    private func contextIDs(clicked track: LibraryTrackDisplay) -> Set<RowID> {
        selection.contains(track.id) ? selection : [track.id]
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
