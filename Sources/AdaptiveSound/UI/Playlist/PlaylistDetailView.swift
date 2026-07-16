import LibraryStore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Playlist detail (S10.3 — the open-playlist content pane)

/// The detail shown when a playlist is selected in the sidebar. Loads through `PlaylistsModel`
/// (entries in position order, each resolved to its library track) and reuses `PlaylistItemRow`
/// (with a `PlaylistEntryDragItem` grip). Chunk C: the three play verbs (Play replaces the queue
/// with a one-level restore-queue undo; Play Next / Add to Queue), tap-to-play-from-row, grip-drag
/// reorder, remove, and ↑/↓/Return/⌫ keys — the same scaffold the queue's `PlaylistItemList` uses.
/// Chunk F renders the unavailable state for an entry whose file moved/was deleted. Several members
/// are `internal` (not `private`) so the same-type `PlaylistDetailView+Actions` extension (split out
/// for type-body length) can reach them.
struct PlaylistDetailView: View {
    let playlistID: Int64
    @Environment(PlaylistsModel.self) var model

    /// Keyboard-selected row (a ScrollView/LazyVStack doesn't own key focus like a `List`).
    @State var selectedEntryID: Int64?
    /// The entry a reorder drag is hovering over (drop-target border). Nil when no drag is active.
    @State private var dropTargetEntryID: Int64?
    @FocusState private var listFocused: Bool
    /// Transient "Restore previous queue" affordance after a Play-replace; the token re-triggers the
    /// auto-dismiss even on a repeated Play.
    @State var restoreToastToken: Int?
    @State var restoreDismissTask: Task<Void, Never>?
    /// The entry being re-pointed via Locate… (drives the file importer); nil when closed (F).
    /// `internal` so the `+Actions` extension's `missingRowActions` can set it.
    @State var locatingEntryID: Int64?
    /// Confirm before the irreversible bulk "Remove missing" (no undo — F review).
    @State private var confirmingRemoveMissing = false

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
        // Locate… (F): pick the moved file → re-point the track (id preserved) → it resolves.
        .fileImporter(
            isPresented: Binding(get: { locatingEntryID != nil },
                                 set: { if !$0 { locatingEntryID = nil } }),
            allowedContentTypes: [.audio]
        ) { result in
            if case let .success(url) = result, let id = locatingEntryID {
                Task { await model.relocateEntry(id, to: url) }
            }
            locatingEntryID = nil
        }
        // A per-action failure (Locate URL-conflict, remove-missing) — a transient alert, NOT the
        // pane-wide load-error state (F review).
        .alert("Couldn’t Complete That", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.clearActionError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
        // Bulk remove is irreversible → confirm (F review).
        .confirmationDialog(
            "Remove \(model.missingEntryCount) missing \(model.missingEntryCount == 1 ? "track" : "tracks")?",
            isPresented: $confirmingRemoveMissing, titleVisibility: .visible
        ) {
            Button("Remove Missing", role: .destructive) { Task { await model.removeMissingEntries() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The playlist entries for files that are missing from disk will be removed. This can’t be undone.")
        }
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
            // Bulk "Remove missing" (F) — only when some entries' files are gone. Disabled during a
            // scan/reconcile (availability is unreliable then — files flicker to "missing").
            if model.missingEntryCount > 0 {
                Menu {
                    Button("Remove \(model.missingEntryCount) Missing", systemImage: "trash", role: .destructive) {
                        confirmingRemoveMissing = true
                    }
                    .disabled(model.isLibraryPopulating)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
                .help(missingHelp)
            }
        }
        .disabled(model.detailState != .loaded)
    }

    private var countLine: String {
        let total = model.detail.count
        let base = "\(total.formatted(.number)) \(total == 1 ? "track" : "tracks")"
        let missing = model.missingEntryCount
        return missing > 0 ? "\(base) · \(missing) unavailable" : base
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
        .defaultFocus($listFocused, true)
        .focusEffectDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.return) { playSelected() }
        .onKeyPress(.delete) { removeSelected() }
    }

    @ViewBuilder
    private func detailRow(index: Int, row: PlaylistDetailEntry) -> some View {
        if row.isAvailable, let display = row.display {
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
            unavailableRow(index: index, row: row)
        }
    }

    /// A missing-file entry (F): its metadata dimmed, with a trailing warning-badge MENU (Locate /
    /// Remove) — a visible, click-and-keyboard-reachable affordance, not just right-click (review).
    /// Not tappable-to-play (skipped on play). VoiceOver reads it as one element + the same actions.
    private func unavailableRow(index: Int, row: PlaylistDetailEntry) -> some View {
        HStack(spacing: 12) {
            Text(index + 1, format: .number.grouping(.never))
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .frame(width: numberColumnWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.display?.title ?? "Unknown Track")
                    .font(DesignSystem.Font.body)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .lineLimit(1)
                if let artist = row.display?.artistName, !artist.isEmpty {
                    Text(artist)
                        .font(DesignSystem.Font.caption)
                        .foregroundStyle(DesignSystem.Color.labelTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Menu {
                missingRowActions(row)
            } label: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("File missing — moved or deleted. Locate… to re-point it, or remove it.")
        }
        .padding(.vertical, DesignSystem.Spacing.xSmall)
        .padding(.horizontal, DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu { missingRowActions(row) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.display?.title ?? "Unknown Track"), unavailable — file missing")
        .accessibilityActions { missingRowActions(row) }
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
}
