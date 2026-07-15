import LibraryStore
import SwiftUI

// MARK: - Playlist detail (S10.3 — the open-playlist content pane)

/// The detail shown when a playlist is selected in the sidebar. Loads through `PlaylistsModel`
/// (entries in position order, each resolved to its library track) and renders the rows READ-ONLY
/// by reusing `PlaylistItemRow` in its no-drag form. Chunk C wires play / remove / reorder onto
/// these SAME rows (tap-to-play, the header play verbs + restore-queue undo, grip-drag reorder);
/// Chunk F renders the unavailable state for an entry whose file moved/was deleted.
struct PlaylistDetailView: View {
    let playlistID: Int64
    @Environment(PlaylistsModel.self) private var model

    /// Track-number column sized to the widest index, so a 3-digit position never wraps (queue idiom).
    private var numberColumnWidth: CGFloat {
        let digits = max(2, String(model.detail.count).count)
        return CGFloat(digits) * 8 + 6
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DesignSystem.Color.window)
        // Reload whenever the selected playlist changes (a new sidebar selection reuses this view).
        .task(id: playlistID) { await model.loadDetail(id: playlistID) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playlist")
                    .font(DesignSystem.Font.micro)
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                Text(model.openPlaylist?.name ?? "Playlist")
                    .font(DesignSystem.Font.sectionTitle)
                    .foregroundStyle(DesignSystem.Color.label)
                    .lineLimit(1)
            }
            Spacer()
            Text(countLine)
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
        }
        .padding(.horizontal, DesignSystem.LayoutMetrics.screenInsetH)
        .padding(.vertical, DesignSystem.Spacing.medium)
    }

    private var countLine: String {
        let count = model.detail.count
        return "\(count.formatted(.number)) \(count == 1 ? "track" : "tracks")"
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch model.detailState {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn’t Load Playlist", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView {
                Label("No Tracks Yet", systemImage: "music.note.list")
            } description: {
                Text("Add songs from your Library to build this playlist.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            trackList
        }
    }

    private var trackList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.detail.enumerated()), id: \.element.id) { index, row in
                    detailRow(index: index, row: row)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func detailRow(index: Int, row: PlaylistDetailEntry) -> some View {
        if let display = row.display {
            // Read-only reuse: nil `dragPayload` → no grip; no tap gesture (Chunk C adds play/reorder).
            PlaylistItemRow(
                file: AudioFile(display),
                index: index,
                isSelected: false,
                isNowPlaying: false,
                numberColumnWidth: numberColumnWidth
            )
        } else {
            // Placeholder for an unresolved track (moved/deleted). Chunk F replaces this with a
            // proper "unavailable" badge + Locate / Remove-missing affordances.
            unavailableRow(index: index)
        }
    }

    private func unavailableRow(index: Int) -> some View {
        HStack(spacing: 12) {
            Text(index + 1, format: .number.grouping(.never))
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .frame(width: numberColumnWidth, alignment: .trailing)
            Text("Track unavailable")
                .font(DesignSystem.Font.body)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
            Spacer()
        }
        .padding(.vertical, DesignSystem.Spacing.xSmall)
        .padding(.horizontal, DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
