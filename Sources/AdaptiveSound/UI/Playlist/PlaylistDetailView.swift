import LibraryStore
import SwiftUI

// MARK: - Playlist detail (S10.3 — the open-playlist content pane)

/// The detail shown when a playlist is selected in the sidebar. Loads through `PlaylistsModel`
/// (entries in position order, each resolved to its library track) and reuses `PlaylistItemRow`
/// (with a `PlaylistEntryDragItem` grip). Chunk C: the three play verbs (Play replaces the queue
/// with a one-level restore-queue undo; Play Next / Add to Queue), tap-to-play-from-row, grip-drag
/// reorder, remove, and ↑/↓/Return/⌫ keys — the same scaffold the queue's `PlaylistItemList` uses.
/// Chunk F renders the unavailable state for an entry whose file moved/was deleted.
struct PlaylistDetailView: View {
    let playlistID: Int64
    @Environment(PlaylistsModel.self) private var model

    /// Keyboard-selected row (a ScrollView/LazyVStack doesn't own key focus like a `List`).
    @State private var selectedEntryID: Int64?
    /// The entry a reorder drag is hovering over (drop-target border). Nil when no drag is active.
    @State private var dropTargetEntryID: Int64?
    @FocusState private var listFocused: Bool
    /// Transient "Restore previous queue" affordance after a Play-replace; the token re-triggers the
    /// auto-dismiss even on a repeated Play.
    @State private var restoreToastToken: Int?
    @State private var restoreDismissTask: Task<Void, Never>?

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
        .overlay(alignment: .bottom) { restoreToast }
        // Reload whenever the selected playlist changes (a new sidebar selection reuses this view).
        .task(id: playlistID) { await model.loadDetail(id: playlistID) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.medium) {
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
            playVerbs
            Text(countLine)
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
        }
        .padding(.horizontal, DesignSystem.LayoutMetrics.screenInsetH)
        .padding(.vertical, DesignSystem.Spacing.medium)
    }

    private var playVerbs: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Button { playNow() } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Color.accent)
            Button { _ = model.playPlaylistNext() } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .labelStyle(.iconOnly)
            .help("Play Next")
            Button { _ = model.appendPlaylist() } label: {
                Label("Add to Queue", systemImage: "text.append")
            }
            .labelStyle(.iconOnly)
            .help("Add to Queue")
        }
        .disabled(model.detailState != .loaded)
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
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.return) { playSelected() }
        .onKeyPress(.delete) { removeSelected() }
    }

    @ViewBuilder
    private func detailRow(index: Int, row: PlaylistDetailEntry) -> some View {
        if let display = row.display {
            PlaylistItemRow(
                file: AudioFile(display),
                index: index,
                isSelected: selectedEntryID == row.id,
                isNowPlaying: false, // "now playing" in a playlist context is deferred (architect #4)
                numberColumnWidth: numberColumnWidth,
                dragPayload: PlaylistEntryDragItem(entryID: row.id),
                isDropTarget: dropTargetEntryID == row.id
            )
            .dropDestination(for: PlaylistEntryDragItem.self) { payloads, _ in
                dropTargetEntryID = nil
                guard let fromID = payloads.first?.entryID else { return false }
                return moveEntry(fromID: fromID, toEntryID: row.id)
            } isTargeted: { targeted in
                dropTargetEntryID = targeted ? row.id : (dropTargetEntryID == row.id ? nil : dropTargetEntryID)
            }
            .simultaneousGesture(TapGesture().onEnded {
                listFocused = true
                selectedEntryID = row.id
                playNow(startingAt: row.id)
            })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { playNow(startingAt: row.id) }
            .contextMenu {
                Button("Play") { playNow(startingAt: row.id) }
                Button("Play Next") { _ = model.playEntryNext(row.id) } // this track, not the whole list
                Divider()
                Button("Remove from Playlist", role: .destructive) {
                    Task { await model.removeEntry(row.id) }
                }
            }
        } else {
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

    // MARK: Restore-queue undo toast

    @ViewBuilder private var restoreToast: some View {
        if restoreToastToken != nil, model.canRestorePreviousQueue {
            HStack(spacing: DesignSystem.Spacing.medium) {
                Text("Queue replaced")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.label)
                Button("Restore previous queue") {
                    model.restorePreviousQueue()
                    dismissRestoreToast()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Color.accent)
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(.bar, in: Capsule())
            .overlay(Capsule().stroke(DesignSystem.Color.hairline, lineWidth: 0.5))
            .padding(.bottom, DesignSystem.Spacing.large)
            .transition(.opacity)
        }
    }

    // MARK: Actions

    /// Play the playlist (replace queue, undoable), optionally from a tapped row, and raise the
    /// transient restore-queue affordance — ONLY if a replace actually happened (an all-unavailable
    /// playlist no-ops, and must not resurface a stale toast from an earlier real Play).
    private func playNow(startingAt entryID: Int64? = nil) {
        if model.playPlaylist(startingAt: entryID) { raiseRestoreToast() }
    }

    private func raiseRestoreToast() {
        let token = (restoreToastToken ?? 0) &+ 1
        restoreToastToken = token
        restoreDismissTask?.cancel()
        restoreDismissTask = Task { [token] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, restoreToastToken == token else { return }
            restoreToastToken = nil
        }
    }

    private func dismissRestoreToast() {
        restoreDismissTask?.cancel()
        restoreToastToken = nil
    }

    /// Move `fromID` to land AT `toEntryID`'s row and persist the new order — matching the queue's
    /// convention (`AudioViewModel.moveByDrop`): dragging DOWN inserts AFTER the target, UP before
    /// it, so the last slot is reachable and the two lists behave identically.
    private func moveEntry(fromID: Int64, toEntryID: Int64) -> Bool {
        var ids = model.detail.map(\.id)
        guard let from = ids.firstIndex(of: fromID), let to = ids.firstIndex(of: toEntryID),
              from != to else { return false }
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: from < to ? to + 1 : to)
        Task { await model.reorderEntries(ids) }
        return true
    }

    /// ↑/↓ traverse only the RESOLVED (playable) rows — the "unavailable" placeholders are
    /// non-interactive until Chunk F, so selection never lands on one.
    private func moveSelection(by delta: Int) -> KeyPress.Result {
        let ids = model.detail.filter { $0.display != nil }.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        guard let current = selectedEntryID, let index = ids.firstIndex(of: current) else {
            selectedEntryID = ids.first
            return .handled
        }
        let next = index + delta
        guard next >= 0, next < ids.count else { return .ignored }
        selectedEntryID = ids[next]
        return .handled
    }

    private func playSelected() -> KeyPress.Result {
        guard let id = selectedEntryID else { return .ignored }
        playNow(startingAt: id)
        return .handled
    }

    private func removeSelected() -> KeyPress.Result {
        guard let id = selectedEntryID else { return .ignored }
        // Pre-select the neighbor (next, else previous) so selection lands there — not back at the
        // top — once the async remove + reload lands (the neighbor id survives the reload).
        let ids = model.detail.map(\.id)
        if let index = ids.firstIndex(of: id) {
            selectedEntryID = index + 1 < ids.count ? ids[index + 1]
                : (index - 1 >= 0 ? ids[index - 1] : nil)
        }
        Task { await model.removeEntry(id) }
        return .handled
    }
}
