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
/// the table subtree. Double-click / Return plays the full ordered list from the row; the context
/// menu mirrors `AlbumDetailView` (Play · Play Next · Add to Queue · — · Info), operating on the
/// selection in sort order for a multi-selection and on the primary row for Info.
private struct SongsTable: View {
    @Environment(LibraryBrowseModel.self) private var model
    @State private var selection = Set<LibraryTrackDisplay.ID>()
    /// The track whose Info popover is open (mirrors the album-detail affordance).
    @State private var infoTarget: LibraryTrackDisplay?

    var body: some View {
        Table(model.songs, selection: $selection) {
            TableColumn("Title") { titleCell($0) }.width(min: 160, ideal: 300)
            TableColumn("Artist") { artistCell($0) }.width(min: 110, ideal: 170)
            TableColumn("Album") { albumCell($0) }.width(min: 110, ideal: 190)
            TableColumn("Time") { timeCell($0) }.width(min: 52, ideal: 60, max: 72)
            TableColumn("Date Added") { dateCell($0) }.width(min: 92, ideal: 112, max: 140)
        }
        // Uniform row height (aids virtualization / the R1 selection-latency measurement).
        .environment(\.defaultMinListRowHeight, DesignSystem.SongsList.rowHeight)
        .scrollContentBackground(.hidden)
        // Native Table double-click = primaryAction; the same modifier hosts the row context menu
        // (macOS targets the right-clicked row, or the whole selection when clicking within it).
        .contextMenu(forSelectionType: LibraryTrackDisplay.ID.self) { ids in
            menuItems(for: ids)
        } primaryAction: { ids in
            _ = playFullOrder(startingAt: ids)
        }
        // Return plays the current selection from its row (double-click is mouse-only in AppKit).
        .onKeyPress(.return) {
            playFullOrder(startingAt: selection) ? .handled : .ignored
        }
        .popover(item: $infoTarget, arrowEdge: .trailing) { track in
            TrackInfoCard(file: AudioFile(track))
        }
    }

    // MARK: Play + context actions

    /// Play the FULL ordered list starting at the first (sort-order) row in `ids` — the double-
    /// click / Return / single-row-Play behavior (the loaded `songs` array IS the play order, D3).
    @discardableResult
    private func playFullOrder(startingAt ids: Set<LibraryTrackDisplay.ID>) -> Bool {
        guard let index = model.songs.firstIndex(where: { ids.contains($0.id) }) else { return false }
        model.play(model.songs, startAt: index)
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
            Button("Play") { model.play(model.songs, startAt: index) } // full ordered list from row
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
}
