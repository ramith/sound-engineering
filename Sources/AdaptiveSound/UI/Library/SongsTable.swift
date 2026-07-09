import Foundation
import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Table (SwiftUI Table over the full in-memory set)

/// The Songs `Table`. Selection lives HERE (not the parent) so selection churn stays isolated to
/// the table subtree. Double-click / Return plays the single clicked row NOW (inserted right after
/// the current track + jump, preserving the existing queue); the context menu mirrors
/// `AlbumDetailView` (Play · Play Next · Add to Queue · — · Info), operating on the selection in
/// sort order for a multi-selection and on the primary row for Info. Columns are customizable
/// (show/hide/reorder/resize + persistence, §11) via `columnCustomization`.
struct SongsTable: View {
    @Environment(LibraryBrowseModel.self) private var model
    @State private var selection = Set<LibraryTrackDisplay.ID>()
    /// The track whose Info popover is open (mirrors the album-detail affordance).
    @State private var infoTarget: LibraryTrackDisplay?
    /// Per-column show/hide + order + width (§11.4). VIEW-side `@AppStorage` via the NATIVE
    /// `TableColumnCustomization` overload (macOS 14+ — NO Codable/JSON bridge): survives the
    /// tab-`switch` teardown AND persists across launches by re-reading `UserDefaults`; an
    /// absent/garbage blob falls back to a fresh default automatically. Shared with the SongsHeader
    /// "Columns" menu through the same key (§5). Bump the `.vN` suffix on any catalog/lock change.
    @AppStorage("songs.columns.v1")
    private var columnCustomization = TableColumnCustomization<LibraryTrackDisplay>()

    var body: some View {
        // Environment yields no binding; a local `@Bindable` provides `$model.sortOrder` for the
        // Table's `sortOrder:` (single source of truth on the model, §3.1/§6 — NOT a re-seeding
        // subtree `@State`, and NOT a hand-rolled `Binding(get:set:)`).
        @Bindable var model = model
        // Rows bind to `visibleSongs` (the filter-narrowed set), NOT `songs` — so play / context /
        // row-resolution below all operate over exactly what's on screen (§6, #3). `sortOrder` stays
        // the model's single-source-of-truth binding: filtering PRESERVES the sort + triangle.
        Table(model.visibleSongs, selection: $selection, sortOrder: $model.sortOrder,
              columnCustomization: $columnCustomization) {
            // Leading artwork thumbnail (design §10.1): the row-art column that consumes
            // `LibraryTrackDisplay.artworkKey`. Non-sortable, fixed width; reuses `AlbumArtworkView`
            // (sync cache-peek, off-main downsample, cancel-on-scroll, `music.note` placeholder).
            // NO `.customizationID` → excluded from customization entirely (§11.0/§3): it can't be
            // hidden, reordered, or resized, so it stays pinned as the leading column. The other 14
            // columns live in `defaultColumns` + `hiddenColumns` — split so this 15-column builder
            // type-checks in reasonable time.
            TableColumn("") { track in
                artworkCell(track)
            }
            .width(32)
            defaultColumns
            hiddenColumns
        }
        // Uniform row height (aids virtualization / the R1 selection-latency measurement).
        .environment(\.defaultMinListRowHeight, DesignSystem.SongsList.rowHeight)
        .scrollContentBackground(.hidden)
        // Dynamic Type clamp (§10.7): the 36pt fixed rows can't grow unbounded, so cap the table at
        // xxLarge. Header / count / filter live OUTSIDE the table and scale normally; the Info
        // popover + `.help` tooltips carry full-fidelity scaling for anyone who needs larger text.
        .dynamicTypeSize(.small ... .xxLarge)
        // Native Table double-click = primaryAction; the same modifier hosts the row context menu
        // (macOS targets the right-clicked row, or the whole selection when clicking within it).
        .contextMenu(forSelectionType: LibraryTrackDisplay.ID.self) { ids in
            menuItems(for: ids)
        } primaryAction: { ids in
            _ = playSingleTrack(startingAt: ids)
        }
        // Return plays the current selection from its row (double-click is mouse-only in AppKit).
        // Type-to-select (§10.5) is the platform `Table`'s NATIVE behavior — typing jumps to the
        // matching row by the active sort column — and needs no custom code; it only requires the
        // Table to hold key focus, which it takes on click (the same focus this `.onKeyPress` and
        // arrow-key navigation rely on). We deliberately do NOT auto-focus the Table on appear: that
        // would hijack the ⌘F search focus and the expected click-to-focus flow.
        .onKeyPress(.return) {
            playSingleTrack(startingAt: selection) ? .handled : .ignored
        }
        // Header click → re-map to a `TrackSort` + DAO re-read. Two-param form (the one-param is
        // deprecated); no `initial:` — firing on the seed would clobber the composite anchor, and
        // `onChange` correctly does not fire on the initial value (§3.1/§6).
        .onChange(of: model.sortOrder) { _, newValue in
            model.applySortOrder(newValue)
            announceSort(newValue)
        }
        // Sort ⇄ customization coexistence (§4/§11.5): hiding the active-sort column clears the
        // triangle — the composite `songSort` still governs order. Idempotent + loop-free (writes
        // `sortOrder`, never `columnCustomization`); this ALSO fires on resize/reorder drags, so it
        // stays the one cheap visibility check. `.onAppear` reconciles ONCE at launch: `sortOrder`
        // reseeds to the Artist anchor each launch and `.onChange` never fires for the initial
        // value, so a persisted "Artist hidden" would otherwise show the triangle on a hidden column.
        .onChange(of: columnCustomization) { _, custom in
            clearSortIfActiveColumnHidden(custom)
        }
        .onAppear { clearSortIfActiveColumnHidden(columnCustomization) }
        .popover(item: $infoTarget, arrowEdge: .trailing) { track in
            TrackInfoCard(file: AudioFile(track))
        }
    }

    // MARK: Sort / customization coexistence (§4 / §11.5)

    /// Clear the sort triangle when the active-sort column is EFFECTIVELY hidden (§4). No-ops when
    /// the sort is already empty, the column is visible, or the active comparator is display-only
    /// (Genre/Artwork have no comparator) — safe to call from both the `columnCustomization`
    /// `.onChange` and the launch `.onAppear`. A comparator can map to MORE THAN ONE column (Quality
    /// + Format both sort by `\.format`); the triangle clears only when EVERY column bearing it is
    /// hidden. Clearing to `[]` (not the hideable Artist anchor) drops the triangle while
    /// `model.songSort` keeps the grouped composite order.
    private func clearSortIfActiveColumnHidden(
        _ custom: TableColumnCustomization<LibraryTrackDisplay>
    ) {
        guard let key = model.sortOrder.first?.keyPath else { return }
        let ids = customizationIDs(forSortKeyPath: key)
        guard !ids.isEmpty, ids.allSatisfy({ !SongsColumns.isVisible($0, in: custom) }) else { return }
        model.sortOrder = []
    }

    /// The `customizationID`(s) of the column(s) whose header carries `keyPath` as its sort
    /// comparator. Function-local table (mirrors `SongSortMapping`): `PartialKeyPath` is not
    /// `Sendable`, so a stored global trips Swift 6 concurrency checking; rebuilding it on the rare
    /// customization change is negligible. Genre/Artwork are absent (no comparator).
    private func customizationIDs(
        forSortKeyPath keyPath: PartialKeyPath<LibraryTrackDisplay>
    ) -> [String] {
        let table: [PartialKeyPath<LibraryTrackDisplay>: [String]] = [
            \LibraryTrackDisplay.title: ["title"],
            \LibraryTrackDisplay.artistName: ["artist"],
            \LibraryTrackDisplay.albumName: ["album"],
            \LibraryTrackDisplay.durationMs: ["time"],
            \LibraryTrackDisplay.dateAdded: ["dateAdded"],
            \LibraryTrackDisplay.format: ["quality", "format"], // both columns sort by `format`
            \LibraryTrackDisplay.year: ["year"],
            \LibraryTrackDisplay.trackNo: ["trackNo"],
            \LibraryTrackDisplay.discNo: ["discNo"],
            \LibraryTrackDisplay.fileSize: ["fileSize"],
            \LibraryTrackDisplay.albumArtistName: ["albumArtist"],
            \LibraryTrackDisplay.playCount: ["playCount"],
        ]
        return table[keyPath] ?? []
    }

    /// Post a VoiceOver announcement on a sort change (§10.7): a header click flips the order, so
    /// screen-reader users hear "Sorted by Artist, ascending". No-op for an empty order (a triangle
    /// cleared by hiding the active column), which `sortAnnouncement` maps to `nil`. Fires only from
    /// the `sortOrder` `.onChange` (real header clicks) — never on the initial seed.
    private func announceSort(_ comparators: [KeyPathComparator<LibraryTrackDisplay>]) {
        guard let text = SongsAccessibility.sortAnnouncement(for: comparators) else { return }
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: Play + context actions

    /// Jump to play the SINGLE row in `ids` now — the double-click / Return / single-row-"Play"
    /// behavior. The clicked track is inserted right after the current track and played
    /// immediately, with the rest of the existing queue preserved (`playTrackNextNow`); it does
    /// NOT dump the whole `songs` list into the queue. Returns false when `ids` resolves to no row.
    @discardableResult
    private func playSingleTrack(startingAt ids: Set<LibraryTrackDisplay.ID>) -> Bool {
        guard let track = SongsRowResolver.primaryRow(in: model.visibleSongs, selection: ids)
        else { return false }
        model.playTrackNextNow(track)
        return true
    }

    /// The selection as tracks in sort order (multi-select verbs operate in this order, §10.6).
    /// Resolved over the visible (filtered) set so a multi-select Play never reaches a hidden row.
    private func orderedTracks(for ids: Set<LibraryTrackDisplay.ID>) -> [LibraryTrackDisplay] {
        SongsRowResolver.orderedSelection(in: model.visibleSongs, selection: ids)
    }

    @ViewBuilder
    private func menuItems(for ids: Set<LibraryTrackDisplay.ID>) -> some View {
        if ids.count > 1 {
            let tracks = orderedTracks(for: ids)
            Button("Play") { model.play(tracks, startAt: 0) } // multi-select plays the subset
            Button("Play Next") { model.playNext(tracks) }
            Button("Add to Queue") { model.append(tracks) }
            Divider()
            Button("Info", systemImage: "info.circle") { infoTarget = tracks.first }
        } else if let track = SongsRowResolver.primaryRow(in: model.visibleSongs, selection: ids) {
            Button("Play") { model.playTrackNextNow(track) } // single track: insert next + jump
            Button("Play Next") { model.playNext([track]) }
            Button("Add to Queue") { model.append([track]) }
            Divider()
            Button("Info", systemImage: "info.circle") { infoTarget = track }
        }
    }
}

// MARK: - Columns (split into sub-builders so the 15-column `body` type-checks)

private extension SongsTable {
    /// The default-VISIBLE columns (§11.2): Title → Year. First-click direction per §3.1 — all
    /// `.forward` except Date Added (`.reverse`, recently-added first). Quality sorts by the
    /// underlying `format` (Format's hidden column shares that comparator). Title is locked
    /// (hide + reorder) via `disabledCustomizationBehavior` (still resizable); every column carries
    /// a stable `.customizationID`. `applySortOrder` maps each keypath + direction → its `TrackSort`.
    @TableColumnBuilder<LibraryTrackDisplay, KeyPathComparator<LibraryTrackDisplay>>
    var defaultColumns: some TableColumnContent<
        LibraryTrackDisplay, KeyPathComparator<LibraryTrackDisplay>
    > {
        TableColumn("Title", sortUsing: KeyPathComparator(\.title, order: .forward)) {
            titleCell($0)
        }
        .width(min: 160, ideal: 300)
        .customizationID("title")
        .disabledCustomizationBehavior([.visibility, .reorder])
        TableColumn("Artist", sortUsing: KeyPathComparator(\.artistName, order: .forward)) {
            artistCell($0)
        }
        .width(min: 110, ideal: 170)
        .customizationID("artist")
        TableColumn("Album", sortUsing: KeyPathComparator(\.albumName, order: .forward)) {
            albumCell($0)
        }
        .width(min: 110, ideal: 190)
        .customizationID("album")
        TableColumn("Time", sortUsing: KeyPathComparator(\.durationMs, order: .forward)) {
            timeCell($0)
        }
        .width(min: 52, ideal: 60, max: 72)
        .customizationID("time")
        TableColumn("Date Added", sortUsing: KeyPathComparator(\.dateAdded, order: .reverse)) {
            dateCell($0)
        }
        .width(min: 92, ideal: 112, max: 140)
        .customizationID("dateAdded")
        TableColumn("Quality", sortUsing: KeyPathComparator(\.format, order: .forward)) {
            qualityCell($0)
        }
        .width(min: 96, ideal: 118, max: 140)
        .customizationID("quality")
        TableColumn("Year", sortUsing: KeyPathComparator(\.year, order: .forward)) {
            yearCell($0)
        }
        .width(min: 44, ideal: 52, max: 64)
        .customizationID("year")
    }

    /// The default-HIDDEN columns (§11.2), in menu order: Track # → Play Count. All carry
    /// `.defaultVisibility(.hidden)`. Play Count is `.reverse` first-click (most-played first).
    /// Genre is DISPLAY-ONLY — no `sortUsing` (a per-row correlated subquery; sorting it is a BR5
    /// temp-b-tree hazard, §11.1/§12.1) ⇒ no header click, no triangle, absent from the sort mapping.
    @TableColumnBuilder<LibraryTrackDisplay, KeyPathComparator<LibraryTrackDisplay>>
    var hiddenColumns: some TableColumnContent<
        LibraryTrackDisplay, KeyPathComparator<LibraryTrackDisplay>
    > {
        TableColumn("Track #", sortUsing: KeyPathComparator(\.trackNo, order: .forward)) {
            trackNoCell($0)
        }
        .width(min: 44, ideal: 52, max: 64)
        .customizationID("trackNo")
        .defaultVisibility(SongsColumns.defaultVisibility(for: "trackNo"))
        TableColumn("Format", sortUsing: KeyPathComparator(\.format, order: .forward)) {
            formatCell($0)
        }
        .width(min: 64, ideal: 80, max: 100)
        .customizationID("format")
        .defaultVisibility(SongsColumns.defaultVisibility(for: "format"))
        TableColumn("Disc #", sortUsing: KeyPathComparator(\.discNo, order: .forward)) {
            discCell($0)
        }
        .width(min: 44, ideal: 52, max: 64)
        .customizationID("discNo")
        .defaultVisibility(SongsColumns.defaultVisibility(for: "discNo"))
        TableColumn("File Size", sortUsing: KeyPathComparator(\.fileSize, order: .forward)) {
            fileSizeCell($0)
        }
        .width(min: 72, ideal: 88, max: 110)
        .customizationID("fileSize")
        .defaultVisibility(SongsColumns.defaultVisibility(for: "fileSize"))
        TableColumn("Album Artist",
                    sortUsing: KeyPathComparator(\.albumArtistName, order: .forward)) {
            albumArtistCell($0)
        }
        .width(min: 110, ideal: 170)
        .customizationID("albumArtist")
        .defaultVisibility(SongsColumns.defaultVisibility(for: "albumArtist"))
        TableColumn("Genre") {
            genreCell($0)
        }
        .width(min: 90, ideal: 130, max: 180)
        .customizationID("genre")
        .defaultVisibility(SongsColumns.defaultVisibility(for: "genre"))
        TableColumn("Play Count", sortUsing: KeyPathComparator(\.playCount, order: .reverse)) {
            playCountCell($0)
        }
        .width(min: 56, ideal: 68, max: 88)
        .customizationID("playCount")
        .defaultVisibility(SongsColumns.defaultVisibility(for: "playCount"))
    }
}

// MARK: - Cells (§10.1 / §11.1 / §12.2 — nil / 0 / sentinel render as blank)

private extension SongsTable {
    /// The always-present leading artwork cell — and the ROW's single VoiceOver element (§10.7 /
    /// §11.6). SwiftUI's value-based `Table` has no per-row accessibility hook, so the one column
    /// that can never be hidden or reordered (Artwork carries no `customizationID`) is made the row:
    /// `children: .ignore` collapses it to one element, the label/value are composed from the TRACK
    /// MODEL (stable no matter which data columns are visible — never derived from cells), Play is
    /// the default action, and Play Next / Add to Queue / Info are custom actions mirroring the
    /// context menu. Every other cell is `.accessibilityHidden`, so the row reads as ONE element
    /// rather than a grid of cells.
    ///
    /// CRITICAL: the accessibility element + its modifiers hang off THIS plain, env-free container
    /// — never directly off `AlbumArtworkView`, which declares `@Environment(LibraryBrowseModel.self)`.
    /// `.accessibilityElement(children:.ignore)` builds an accessibility representation whose
    /// `DynamicBody` is updated in a DETACHED graph host during the accessibility-preferences pass
    /// (`GraphHost.updatePreferences`) fired by a sort-driven re-layout. That host does not thread
    /// the injected observable, so representing an `@Environment(Object.self)`-bearing view there
    /// re-reads a missing object → `EnvironmentValues.subscript.getter` assertion (EXC_BREAKPOINT on
    /// any header click). A plain `ZStack` has no dynamic properties to update, and `children:.ignore`
    /// keeps the env-reading `AlbumArtworkView` off the a11y host entirely. This mirrors the working
    /// `AlbumCell`, which already hangs identical a11y off its plain `VStack`.
    func artworkCell(_ track: LibraryTrackDisplay) -> some View {
        ZStack {
            AlbumArtworkView(key: track.artworkKey, side: DesignSystem.SongsList.artwork, model: model)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SongsAccessibility.rowLabel(for: track))
        .accessibilityValue(SongsAccessibility.rowValue(for: track))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.playTrackNextNow(track) } // default = Play (insert-next + jump)
        .accessibilityAction(named: Text("Play Next")) { model.playNext([track]) }
        .accessibilityAction(named: Text("Add to Queue")) { model.append([track]) }
        .accessibilityAction(named: Text("Info")) { infoTarget = track }
    }

    func titleCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.title)
            .font(DesignSystem.Font.body)
            .foregroundStyle(DesignSystem.Color.label)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(track.title) // truncated title → full text on hover (VO reads the row label)
            .accessibilityHidden(true) // the Artwork cell is the row's single VO element (§10.7)
    }

    func artistCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.artistName) // "" when the track has no artist → blank cell
            .font(DesignSystem.Font.body)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(track.artistName)
            .accessibilityHidden(true)
    }

    func albumCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.albumName ?? "") // nil album → blank cell
            .font(DesignSystem.Font.body)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(track.albumName ?? "")
            .accessibilityHidden(true)
    }

    func timeCell(_ track: LibraryTrackDisplay) -> some View {
        Text(formatDuration(track.durationSeconds))
            .font(DesignSystem.Font.body)
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true) // duration is spoken via the row label (spelled out)
    }

    func dateCell(_ track: LibraryTrackDisplay) -> some View {
        Text(compactDate(track.dateAdded)) // 0 / unknown → blank
            .font(DesignSystem.Font.caption)
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true) // added-date is spoken via the row value
    }

    func qualityCell(_ track: LibraryTrackDisplay) -> some View {
        // format is NOT NULL — never blank (bare codec when rate/depth are unknown).
        Text(qualityString(format: track.format, sampleRate: track.sampleRate, bitDepth: track.bitDepth))
            .font(DesignSystem.Font.body)
            .fontDesign(.monospaced)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(qualityString(format: track.format, sampleRate: track.sampleRate, bitDepth: track.bitDepth))
            .accessibilityHidden(true) // quality is spoken via the row value
    }

    func yearCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.year.flatMap { $0 > 0 ? String($0) : nil } ?? "") // 0 / nil → blank
            .font(DesignSystem.Font.body)
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true) // year is spoken via the row value
    }

    func trackNoCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.trackNo.flatMap { $0 > 0 ? String($0) : nil } ?? "") // nil / 0 → blank
            .font(DesignSystem.Font.body)
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true)
    }

    func formatCell(_ track: LibraryTrackDisplay) -> some View {
        // Bare container codec — `format` is NOT NULL → never blank (vs. Quality's format+depth/rate).
        Text(track.format)
            .font(DesignSystem.Font.body)
            .fontDesign(.monospaced)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(track.format)
            .accessibilityHidden(true)
    }

    func discCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.discNo.flatMap { $0 > 0 ? String($0) : nil } ?? "") // nil / 0 → blank
            .font(DesignSystem.Font.body)
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true)
    }

    func fileSizeCell(_ track: LibraryTrackDisplay) -> some View {
        // track.fileSize is NOT NULL; 0 (never legitimately observed) still renders blank.
        Text(track.fileSize > 0 ? track.fileSize.formatted(.byteCount(style: .file)) : "")
            .font(DesignSystem.Font.body)
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true)
    }

    func albumArtistCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.albumArtistName ?? "") // nil (incl. the id-0 "Unknown Artist" sentinel) → blank
            .font(DesignSystem.Font.body)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(track.albumArtistName ?? "")
            .accessibilityHidden(true)
    }

    func genreCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.genreName ?? "") // nil (no genre) → blank
            .font(DesignSystem.Font.body)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(track.genreName ?? "")
            .accessibilityHidden(true)
    }

    func playCountCell(_ track: LibraryTrackDisplay) -> some View {
        // 0 → blank (avoid a wall of zeros; every value is 0 until a play-tracking write lands).
        Text(track.playCount > 0 ? track.playCount.formatted(.number) : "")
            .font(DesignSystem.Font.body)
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true)
    }
}
