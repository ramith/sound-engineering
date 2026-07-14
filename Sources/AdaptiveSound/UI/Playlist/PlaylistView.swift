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
                if viewModel.queue.isEmpty {
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
            let count = viewModel.queue.count
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
            if panelMode == .upNext, !viewModel.queue.isEmpty {
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

    /// The row a reorder drag is currently hovering over (drives the drop-target border). Nil when
    /// no drag is in progress.
    @State private var dropTargetIndex: Int?

    /// Keyboard-command focus for the scroll area. `List` owned key focus for free; a
    /// ScrollView/LazyVStack does not, so the ↑/↓/Return/Space/Delete shortcuts are bound to this
    /// (`.focused` + default + set-on-tap) — the same pattern `FrequencyResponseCanvas` uses.
    @FocusState private var queueFocused: Bool

    /// Track-number column width sized to the widest index in the list (~8 pt per monospaced
    /// digit + slack), so a 190-track list reserves room for 3 digits and never wraps "191".
    private var numberColumnWidth: CGFloat {
        let digits = max(2, String(viewModel.queue.count).count)
        return CGFloat(digits) * 8 + 6
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.queue.enumerated()), id: \.element.id) { index, item in
                        queueRow(index: index, item: item)
                    }
                }
            }
            // The queue moved off `List` because a List row's `.dropDestination` never fires (an
            // Apple limitation, forum 730367) — so grip drag-and-drop reorder works here.
            // `.focusable` + `.focused` + `.defaultFocus` restore the key-command target that
            // `List` provided for free (a row tap also sets it); `.focusEffectDisabled` suppresses
            // the focus ring on the scroll area (the selection tint is the cue).
            .focusable()
            .focused($queueFocused)
            .defaultFocus($queueFocused, true)
            .focusEffectDisabled()
            .frame(maxHeight: .infinity)
            // Dismiss any open Info popover when the queue changes (remove / clear / reorder)
            // so a stale target can't match — and re-present on — a different row.
            .onChange(of: viewModel.queue.map(\.id)) { _, _ in
                infoTarget = nil
            }
            .onKeyPress(.upArrow) { moveSelection(by: -1) }
            .onKeyPress(.downArrow) { moveSelection(by: 1) }
            .onKeyPress(.return) { togglePlayIfSelected() }
            .onKeyPress(.space) { togglePlayIfSelected() }
            .onKeyPress(.delete) {
                guard let index = viewModel.selectedTrackIndex else { return .ignored }
                viewModel.removeTrack(at: index)
                return .handled
            }
            // Scroll the current track into view when the header's "Jump to Now Playing" fires (UI-2).
            // Target the row's stable id (matches `.id(item.id)`), not a positional index.
            .onChange(of: jumpToCurrentRequestID) { _, _ in
                guard let index = viewModel.selectedTrackIndex, index < viewModel.queue.count else { return }
                withAnimation { proxy.scrollTo(viewModel.queue[index].id, anchor: .center) }
            }
        } // ScrollViewReader
    }

    private func queueRow(index: Int, item: QueueItem) -> some View {
        PlaylistItemRow(
            file: item.file,
            index: index,
            isSelected: viewModel.selectedTrackIndex == index,
            isNowPlaying: viewModel.isPlaying && viewModel.selectedTrackIndex == index,
            numberColumnWidth: numberColumnWidth,
            dragPayload: QueueDragItem(id: item.id),
            isDropTarget: dropTargetIndex == index
        )
        // Identity is the stable `QueueItem.id` (matches the `ForEach` key) so reorders re-render
        // the RIGHT rows — a positional `.id(index)` fought the ForEach key and left stale
        // now-playing highlights + un-refreshed rows after a move. `scrollTo` uses this id too.
        .id(item.id)
        // Reorder: the grip is the `.draggable` source, each row a `.dropDestination` that lands
        // the dragged item at its position. This is why the queue is a LazyVStack, not a List.
        .dropDestination(for: QueueDragItem.self) { payloads, _ in
            dropTargetIndex = nil
            guard let fromID = payloads.first?.id else { return false }
            return viewModel.moveByDrop(fromID: fromID, toIndex: index)
        } isTargeted: { targeted in
            dropTargetIndex = targeted ? index : (dropTargetIndex == index ? nil : dropTargetIndex)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                queueFocused = true // a click on a row focuses the queue for the keyboard shortcuts
                // Single-click plays the row, so the now-playing card always matches the audio (no
                // select-without-play state). Re-clicking the playing track is a no-op (no restart).
                guard !(viewModel.isPlaying && viewModel.selectedTrackIndex == index) else { return }
                viewModel.playTrack(at: index)
            }
        )
        .accessibilityAddTraits(.isButton)
        // VoiceOver "activate" — the tap is a gesture VO can't trigger, so bind the play action.
        .accessibilityAction { viewModel.playTrack(at: index) }
        .contextMenu { queueRowMenu(index: index, item: item) }
        .popover(
            isPresented: Binding(
                get: { infoTarget?.id == item.id },
                set: { if !$0 { infoTarget = nil } }
            ),
            arrowEdge: .trailing
        ) {
            TrackInfoCard(file: item.file)
        }
    }

    @ViewBuilder
    private func queueRowMenu(index: Int, item: QueueItem) -> some View {
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
        .disabled(index >= viewModel.queue.count - 1)
        Button("Move to Bottom", systemImage: "arrow.down.to.line") {
            viewModel.moveTrackToBottom(index)
        }
        .disabled(index >= viewModel.queue.count - 1)
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

    /// Move the selection by `delta` rows, clamped to the queue (keyboard ↑/↓). `.ignored` when
    /// there's no selection or the move would leave the queue, so the event can bubble.
    private func moveSelection(by delta: Int) -> KeyPress.Result {
        guard let current = viewModel.selectedTrackIndex else { return .ignored }
        let next = current + delta
        guard next >= 0, next < viewModel.queue.count else { return .ignored }
        viewModel.selectedTrackIndex = next
        return .handled
    }

    /// Toggle play/pause for the selected row (keyboard Return/Space). `.ignored` when nothing is
    /// selected so the key can do its default thing.
    private func togglePlayIfSelected() -> KeyPress.Result {
        guard viewModel.selectedTrackIndex != nil else { return .ignored }
        viewModel.togglePlayPause()
        return .handled
    }
}
