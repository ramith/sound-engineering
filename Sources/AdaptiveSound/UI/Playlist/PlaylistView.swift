import SwiftUI

// MARK: - Queue View (the current playback queue — S9 IA change)

/// The Now Playing queue: ONLY the current play queue, built by the Library's Play / Play Next /
/// Add to Queue verbs. Folder-loading moved to the Library section (design §4/§5), so there is no
/// folder chooser or "~/…" chip here anymore, and choosing a folder never rewrites this list.
struct PlaylistView: View {
    @Environment(AudioViewModel.self) var viewModel
    /// Bumped by the header's "Jump to Now Playing" button; observed by the list to scroll the
    /// current track into view (UI-2). A monotonic request-ID (not a Bool) so repeated presses
    /// re-fire even when the value would otherwise be unchanged.
    @State private var jumpToCurrentRequestID = 0
    /// Up Next (the live queue) vs. History (this session's plays). Local view state — the panel
    /// simply switches which list it shows (S10.2 3a).
    @State private var panelMode: QueuePanelMode = .upNext

    var body: some View {
        VStack(spacing: 12) {
            PlaylistHeaderView(jumpToCurrentRequestID: $jumpToCurrentRequestID, panelMode: $panelMode)
            Picker("View", selection: $panelMode) {
                ForEach(QueuePanelMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch panelMode {
            case .upNext:
                if viewModel.playlist.isEmpty {
                    emptyQueue
                } else {
                    PlaylistItemList(jumpToCurrentRequestID: $jumpToCurrentRequestID)
                }
            case .history:
                QueueHistoryList()
            }
        }
    }

    /// Shown whenever the queue is empty (fresh launch, or after Clear Queue). The queue is now
    /// filled from the Library, so the primary action is a doorway to it (design §4).
    private var emptyQueue: some View {
        ContentUnavailableView {
            Label("Queue is Empty", systemImage: "play.square.stack")
        } description: {
            Text("Browse your Library and press Play to start listening.")
        } actions: {
            Button("Browse Library") { viewModel.selectedTab = .library }
                .buttonStyle(.borderedProminent)
                .tint(Color.asAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Queue Header

private struct PlaylistHeaderView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Binding var jumpToCurrentRequestID: Int
    @Binding var panelMode: QueuePanelMode

    /// Mode-aware subtitle: the queue's track count, or the number of session plays.
    private var subtitle: String {
        switch panelMode {
        case .upNext:
            let count = viewModel.playlist.count
            return "\(count) \(count == 1 ? "track" : "tracks")"
        case .history:
            let count = viewModel.sessionHistory.count
            return "\(count) played"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(panelMode == .history ? "History" : "Queue")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.asLabelSecond)

                Text(subtitle)
                    .font(DesignSystem.Font.monoSmall)
                    .foregroundStyle(Color.asLabelTertiary)
            }

            Spacer()

            PlaylistControlsView(jumpToCurrentRequestID: $jumpToCurrentRequestID, panelMode: $panelMode)
        }
    }
}

// MARK: - Queue Controls

private struct PlaylistControlsView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Binding var jumpToCurrentRequestID: Int
    @Binding var panelMode: QueuePanelMode

    var body: some View {
        HStack(spacing: 8) {
            // Clear Queue — Up Next only, and only when there's something to clear. Immediate
            // (no confirm, founder §3): the queue is cheap to rebuild and History is left intact.
            if panelMode == .upNext, !viewModel.playlist.isEmpty {
                Button("Clear Queue", systemImage: "trash", action: viewModel.clearPlaylist)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.asLabelSecond)
                    .help("Clear the queue (keeps History)")
            }

            // Shuffle toggle
            Button(
                "Shuffle",
                systemImage: viewModel.shuffleEnabled ? "shuffle.circle.fill" : "shuffle.circle",
                action: viewModel.toggleShuffle
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 14))
            .foregroundStyle(viewModel.shuffleEnabled ? Color.asAccent : Color.asLabelSecond)
            .accessibilityLabel("Shuffle: \(viewModel.shuffleEnabled ? "on" : "off")")
            .help("Shuffle: \(viewModel.shuffleEnabled ? "On" : "Off")")

            // Repeat mode toggle
            Button(
                "Repeat",
                systemImage: viewModel.repeatMode == 2 ? "repeat.1.circle.fill"
                    : viewModel.repeatMode == 1 ? "repeat.circle.fill"
                    : "repeat.circle",
                action: viewModel.cycleRepeatMode
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 14))
            .foregroundStyle(viewModel.repeatMode > 0 ? Color.asAccent : Color.asLabelSecond)
            .accessibilityLabel("Repeat mode: \(["off", "all", "one"][viewModel.repeatMode])")
            .help(["Off", "All", "One"][viewModel.repeatMode])

            // Jump to now-playing
            if viewModel.selectedTrackIndex != nil {
                Button("Jump to Now Playing", systemImage: "play.circle.fill") {
                    // Signal the list to scroll the current track into view (UI-2). The list owns
                    // the ScrollViewReader proxy; bumping this request-ID triggers its onChange.
                    jumpToCurrentRequestID += 1
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 14))
                .foregroundStyle(Color.asAccent)
                .help("Jump to now playing")
            }
        }
    }
}

// MARK: - Playlist Item List

private struct PlaylistItemList: View {
    @Environment(AudioViewModel.self) var viewModel
    @Binding var jumpToCurrentRequestID: Int

    /// Non-nil while the "Info" popover is showing; identifies which row's card is open by its
    /// stable `QueueItem.id` (dups-safe — keying on the URL popped the card on every duplicate row).
    /// Only one row presents at a time — the per-row `Binding<Bool>` is derived from this.
    @State private var infoTarget: QueueItem?

    /// The row whose drag-handle the pointer is currently over. Gates `.moveDisabled` so exactly
    /// that row is drag-reorderable while its grip is hovered (see the row's `.moveDisabled`).
    @State private var dragHandleHoverIndex: Int?

    /// Track-number column width sized to the widest index in the list (~8 pt per monospaced
    /// digit + slack), so a 190-track list reserves room for 3 digits and never wraps "191".
    private var numberColumnWidth: CGFloat {
        let digits = max(2, String(viewModel.playlist.count).count)
        return CGFloat(digits) * 8 + 6
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // Materialized to `Array` (rather than iterating the raw `.enumerated()` sequence)
                // so `Data.Index` is a plain `Int`, matching what `List`'s native macOS row-drag
                // reordering has always been tested against. `EnumeratedSequence` only recently
                // gained a conditional `RandomAccessCollection` conformance with its own opaque
                // index type, and that combination silently prevented `.onMove` from initiating a
                // drag here — this is the "reliable" pattern for a reorderable, indexed `ForEach`.
                ForEach(Array(viewModel.queue.enumerated()), id: \.element.id) { index, item in
                    PlaylistItemRow(
                        file: item.file,
                        index: index,
                        isSelected: viewModel.selectedTrackIndex == index,
                        isNowPlaying: viewModel.isPlaying && viewModel.selectedTrackIndex == index,
                        numberColumnWidth: numberColumnWidth,
                        onDragHandleHover: { hovering in
                            dragHandleHoverIndex = hovering
                                ? index
                                : (dragHandleHoverIndex == index ? nil : dragHandleHoverIndex)
                        }
                    )
                    .id(index)
                    // Drag-to-reorder vs. tap-to-play conflict (FB7367473: a row tap action kills
                    // `.onMove` drag on macOS). Fix per nilcoalescing: keep the row `.moveDisabled`
                    // by DEFAULT — so the tap recognizer below owns the click — and re-enable move
                    // ONLY while the pointer is over the leading grip handle, so a drag starts from
                    // there. `.onHover` isn't updated mid-drag, so the row stays draggable until drop.
                    .moveDisabled(dragHandleHoverIndex != index)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            // Single-click plays the row, so the now-playing card always matches the
                            // audio (no select-without-play state). Re-clicking the track that's
                            // already playing is a no-op so it doesn't restart from the top.
                            guard !(viewModel.isPlaying && viewModel.selectedTrackIndex == index) else { return }
                            viewModel.playTrack(at: index)
                        }
                    )
                    .accessibilityAddTraits(.isButton)
                    .contextMenu {
                        Button("Move to Top", systemImage: "arrow.up.to.line") {
                            viewModel.moveTrackToTop(index)
                        }
                        .disabled(index == 0)
                        Button("Move Up", systemImage: "arrow.up") {
                            viewModel.moveTrackUp(index)
                        }
                        .disabled(index == 0)
                        Button("Move Down", systemImage: "arrow.down") {
                            viewModel.moveTrackDown(index)
                        }
                        .disabled(index >= viewModel.playlist.count - 1)
                        Button("Move to Bottom", systemImage: "arrow.down.to.line") {
                            viewModel.moveTrackToBottom(index)
                        }
                        .disabled(index >= viewModel.playlist.count - 1)
                        Divider()
                        Button("Info", systemImage: "info.circle") {
                            infoTarget = item
                        }
                        Divider()
                        Button("Remove from Queue", systemImage: "trash") {
                            viewModel.removeTrack(at: index)
                        }
                        Button("Clear Queue", systemImage: "clear") {
                            viewModel.clearPlaylist()
                        }
                    }
                    .popover(
                        isPresented: Binding(
                            get: { infoTarget?.id == item.id },
                            set: { if !$0 { infoTarget = nil } }
                        ),
                        arrowEdge: .trailing
                    ) {
                        TrackInfoCard(file: item.file)
                    }
                    .onKeyPress(.delete) {
                        viewModel.removeTrack(at: index)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        if index > 0 {
                            viewModel.selectedTrackIndex = index - 1
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if index < viewModel.playlist.count - 1 {
                            viewModel.selectedTrackIndex = index + 1
                        }
                        return .handled
                    }
                    .onKeyPress(.return) {
                        if viewModel.selectedTrackIndex == index {
                            viewModel.togglePlayPause()
                        }
                        return .handled
                    }
                    .onKeyPress(.space) {
                        if viewModel.selectedTrackIndex == index {
                            viewModel.togglePlayPause()
                        }
                        return .handled
                    }
                }
                .onMove { source, destination in
                    viewModel.movePlaylistItems(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: .infinity)
            // Dismiss any open Info popover when the queue changes (remove / clear / reorder)
            // so a stale target can't match — and re-present on — a different row.
            .onChange(of: viewModel.queue.map(\.id)) { _, _ in
                infoTarget = nil
            }
            // Global keyboard shortcuts for the playlist
            .onKeyPress(.upArrow) {
                if let current = viewModel.selectedTrackIndex, current > 0 {
                    viewModel.selectedTrackIndex = current - 1
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.downArrow) {
                if let current = viewModel.selectedTrackIndex,
                   current < viewModel.playlist.count - 1 {
                    viewModel.selectedTrackIndex = current + 1
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.return) {
                if viewModel.selectedTrackIndex != nil {
                    viewModel.togglePlayPause()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.space) {
                if viewModel.selectedTrackIndex != nil {
                    viewModel.togglePlayPause()
                    return .handled
                }
                return .ignored
            }
            // Scroll the current track into view when the header's "Jump to Now Playing" fires (UI-2).
            .onChange(of: jumpToCurrentRequestID) { _, _ in
                guard let index = viewModel.selectedTrackIndex else { return }
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        } // ScrollViewReader
    }
}
