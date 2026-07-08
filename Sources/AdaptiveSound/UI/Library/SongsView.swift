import Foundation
import LibraryStore
import SwiftUI

// MARK: - Songs list (S9.5 — slice 2 shell)

/// The Library's default landing: a flat, full-library `Table` of every track over the
/// in-memory full-load set (`LibraryBrowseModel.songs`, OD-1). This slice is the core text
/// shell — Title · Artist · Album · Time · Date Added, the composite default order, double-click /
/// Return play-from-row, and the "N songs · total" count. Artwork / Format-Quality / Year columns,
/// sortable headers, search, and the A–Z rail land in later slices.
///
/// State handling mirrors `AlbumGridView`: a `.task(id:)` keyed on store-readiness kicks the
/// full-load, and `.onChange(of: libraryRevision)` (in `LibraryTabView`) reloads once per pass.
/// Header + table are shown only when there ARE rows; otherwise the spinner / empty / first-run /
/// scanning / failed states delegate to `LibraryEmptyStateView` (no new case).
struct SongsView: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        content
            // Keyed on store-readiness so a Library visit BEFORE the async store finishes building
            // reloads once it's ready (mirrors AlbumGridView / review S2) — not a stuck spinner.
            .task(id: model.isStoreReady) { await model.loadSongs() }
    }

    @ViewBuilder private var content: some View {
        switch model.songsState {
        case .idle, .loading:
            if model.songs.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                songsList // keep showing cached rows while a refresh is in flight
            }
        case .loaded:
            // `.loaded` but empty means every track was removed — a genuine empty library.
            if model.songs.isEmpty { LibraryEmptyStateView(kind: .emptyLibrary) } else { songsList }
        case .firstRun:
            // A scan kicked off from the first-run CTA flips this to a truthful "scanning" until
            // rows land; otherwise it's the add-a-folder call to action.
            LibraryEmptyStateView(kind: model.isPopulating ? .scanning : .firstRun)
        case .empty:
            // Roots exist, zero tracks: scanning if a pass is live, else a genuine "no music".
            LibraryEmptyStateView(kind: model.isPopulating ? .scanning : .emptyLibrary)
        case let .failed(message):
            LibraryEmptyStateView(kind: .failed(message))
        }
    }

    /// Header + hairline + table — shown only when there is content (design §10.3).
    private var songsList: some View {
        VStack(spacing: 0) {
            SongsHeader()
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            SongsTable()
        }
    }
}

// MARK: - Header (count line only for this slice; search field lands in slice 4)

/// The Songs header band: a leading "N songs · total duration" count. Kept a separate view (reads
/// only `model.songs`, never the table's selection) so a selection change never re-sums the total.
private struct SongsHeader: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        HStack {
            Text(countLine)
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
            Spacer(minLength: DesignSystem.Spacing.small)
        }
        .padding(.horizontal, DesignSystem.LayoutMetrics.screenInsetH)
        .frame(height: DesignSystem.SongsList.headerHeight)
    }

    /// "1,240 songs · 3 hr 14 min" (grouped thousands; singular "1 song"). Filtered "N results"
    /// is slice 4.
    private var countLine: String {
        let count = model.songs.count
        let noun = count == 1 ? "song" : "songs"
        let total = humaneTotalDuration(model.songs.reduce(0.0) { $0 + $1.durationSeconds })
        return "\(count.formatted(.number)) \(noun) · \(total)"
    }
}

// MARK: - Table (SwiftUI Table over the full in-memory set)

/// The Songs `Table`. Selection lives HERE (not the parent) so selection churn stays isolated to
/// the table subtree. Double-click / Return plays the single clicked row NOW (inserted right after
/// the current track + jump, preserving the existing queue); the context menu mirrors
/// `AlbumDetailView` (Play · Play Next · Add to Queue · — · Info), operating on the selection in
/// sort order for a multi-selection and on the primary row for Info.
private struct SongsTable: View {
    @Environment(LibraryBrowseModel.self) private var model
    @State private var selection = Set<LibraryTrackDisplay.ID>()
    /// The track whose Info popover is open (mirrors the album-detail affordance).
    @State private var infoTarget: LibraryTrackDisplay?

    var body: some View {
        // Environment yields no binding; a local `@Bindable` provides `$model.sortOrder` for the
        // Table's `sortOrder:` (single source of truth on the model, §3.1/§6 — NOT a re-seeding
        // subtree `@State`, and NOT a hand-rolled `Binding(get:set:)`).
        @Bindable var model = model
        Table(model.songs, selection: $selection, sortOrder: $model.sortOrder) {
            // First-click direction per §3.1: all `.forward` except Date Added (`.reverse`,
            // recently-added first). Quality sorts by the underlying `format`. `applySortOrder`
            // maps each keypath + direction → its asc/desc `TrackSort`.
            TableColumn("Title", sortUsing: KeyPathComparator(\.title, order: .forward)) {
                titleCell($0)
            }.width(min: 160, ideal: 300)
            TableColumn("Artist", sortUsing: KeyPathComparator(\.artistName, order: .forward)) {
                artistCell($0)
            }.width(min: 110, ideal: 170)
            TableColumn("Album", sortUsing: KeyPathComparator(\.albumName, order: .forward)) {
                albumCell($0)
            }.width(min: 110, ideal: 190)
            TableColumn("Time", sortUsing: KeyPathComparator(\.durationMs, order: .forward)) {
                timeCell($0)
            }.width(min: 52, ideal: 60, max: 72)
            TableColumn("Date Added", sortUsing: KeyPathComparator(\.dateAdded, order: .reverse)) {
                dateCell($0)
            }.width(min: 92, ideal: 112, max: 140)
            // S9.5 §12.1 full-catalog columns (backend delta): fixed/always-visible for this
            // chunk — show/hide customization lands in the later slice-3 UI (§11).
            TableColumn("Quality", sortUsing: KeyPathComparator(\.format, order: .forward)) {
                qualityCell($0)
            }.width(min: 96, ideal: 118, max: 140)
            TableColumn("Year", sortUsing: KeyPathComparator(\.year, order: .forward)) {
                yearCell($0)
            }.width(min: 44, ideal: 52, max: 64)
            TableColumn("Disc #", sortUsing: KeyPathComparator(\.discNo, order: .forward)) {
                discCell($0)
            }.width(min: 44, ideal: 52, max: 64)
            TableColumn("File Size", sortUsing: KeyPathComparator(\.fileSize, order: .forward)) {
                fileSizeCell($0)
            }.width(min: 72, ideal: 88, max: 110)
        }
        // Uniform row height (aids virtualization / the R1 selection-latency measurement).
        .environment(\.defaultMinListRowHeight, DesignSystem.SongsList.rowHeight)
        .scrollContentBackground(.hidden)
        // Native Table double-click = primaryAction; the same modifier hosts the row context menu
        // (macOS targets the right-clicked row, or the whole selection when clicking within it).
        .contextMenu(forSelectionType: LibraryTrackDisplay.ID.self) { ids in
            menuItems(for: ids)
        } primaryAction: { ids in
            _ = playSingleTrack(startingAt: ids)
        }
        // Return plays the current selection from its row (double-click is mouse-only in AppKit).
        .onKeyPress(.return) {
            playSingleTrack(startingAt: selection) ? .handled : .ignored
        }
        // Header click → re-map to a `TrackSort` + DAO re-read. Two-param form (the one-param is
        // deprecated); no `initial:` — firing on the seed would clobber the composite anchor, and
        // `onChange` correctly does not fire on the initial value (§3.1/§6).
        .onChange(of: model.sortOrder) { _, newValue in
            model.applySortOrder(newValue)
        }
        .popover(item: $infoTarget, arrowEdge: .trailing) { track in
            TrackInfoCard(file: AudioFile(track))
        }
    }

    // MARK: Play + context actions

    /// Jump to play the SINGLE row in `ids` now — the double-click / Return / single-row-"Play"
    /// behavior. The clicked track is inserted right after the current track and played
    /// immediately, with the rest of the existing queue preserved (`playTrackNextNow`); it does
    /// NOT dump the whole `songs` list into the queue. Returns false when `ids` resolves to no row.
    @discardableResult
    private func playSingleTrack(startingAt ids: Set<LibraryTrackDisplay.ID>) -> Bool {
        guard let index = model.songs.firstIndex(where: { ids.contains($0.id) }) else { return false }
        model.playTrackNextNow(model.songs[index])
        return true
    }

    /// The selection as tracks in sort order (multi-select verbs operate in this order, §10.6).
    private func orderedTracks(for ids: Set<LibraryTrackDisplay.ID>) -> [LibraryTrackDisplay] {
        model.songs.filter { ids.contains($0.id) }
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
        } else if let index = model.songs.firstIndex(where: { ids.contains($0.id) }) {
            let track = model.songs[index]
            Button("Play") { model.playTrackNextNow(track) } // single track: insert next + jump
            Button("Play Next") { model.playNext([track]) }
            Button("Add to Queue") { model.append([track]) }
            Divider()
            Button("Info", systemImage: "info.circle") { infoTarget = track }
        }
    }

    // MARK: Cells (§10.1 — empty artist / nil album render as blank)

    private func titleCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.title)
            .font(DesignSystem.Font.body)
            .foregroundStyle(DesignSystem.Color.label)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func artistCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.artistName) // "" when the track has no artist → blank cell
            .font(DesignSystem.Font.body)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func albumCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.albumName ?? "") // nil album → blank cell
            .font(DesignSystem.Font.body)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeCell(_ track: LibraryTrackDisplay) -> some View {
        Text(formatDuration(track.durationSeconds))
            .font(DesignSystem.Font.body)
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func dateCell(_ track: LibraryTrackDisplay) -> some View {
        Text(compactDate(track.dateAdded)) // 0 / unknown → blank
            .font(DesignSystem.Font.caption)
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Cells — S9.5 §12.1 full-catalog columns

    private func qualityCell(_ track: LibraryTrackDisplay) -> some View {
        // format is NOT NULL — never blank (bare codec when rate/depth are unknown).
        Text(qualityString(format: track.format, sampleRate: track.sampleRate, bitDepth: track.bitDepth))
            .font(DesignSystem.Font.body)
            .fontDesign(.monospaced)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func yearCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.year.flatMap { $0 > 0 ? String($0) : nil } ?? "") // 0 / nil → blank
            .font(DesignSystem.Font.body)
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func discCell(_ track: LibraryTrackDisplay) -> some View {
        Text(track.discNo.flatMap { $0 > 0 ? String($0) : nil } ?? "") // nil / 0 → blank
            .font(DesignSystem.Font.body)
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func fileSizeCell(_ track: LibraryTrackDisplay) -> some View {
        // track.fileSize is NOT NULL; 0 (never legitimately observed) still renders blank.
        Text(track.fileSize > 0 ? Self.byteCountFormatter.string(fromByteCount: track.fileSize) : "")
            .font(DesignSystem.Font.body)
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
