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

    var body: some View {
        VStack(spacing: 12) {
            PlaylistHeaderView(jumpToCurrentRequestID: $jumpToCurrentRequestID)
            if viewModel.playlist.isEmpty {
                emptyQueue
            } else {
                PlaylistItemList(jumpToCurrentRequestID: $jumpToCurrentRequestID)
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Queue")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.asLabelSecond)

                Text("\(viewModel.playlist.count) \(viewModel.playlist.count == 1 ? "track" : "tracks")")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.asLabelTertiary)
            }

            Spacer()

            PlaylistControlsView(jumpToCurrentRequestID: $jumpToCurrentRequestID)
        }
    }
}

// MARK: - Queue Controls

private struct PlaylistControlsView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Binding var jumpToCurrentRequestID: Int

    var body: some View {
        HStack(spacing: 8) {
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

    /// Non-nil while the "Info" popover is showing; identifies which row's card is open.
    /// Only one row presents at a time — the per-row `Binding<Bool>` is derived from this.
    @State private var infoTarget: AudioFile?

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
                ForEach(Array(viewModel.playlist.enumerated()), id: \.element.id) { index, file in
                    PlaylistItemRow(
                        file: file,
                        index: index,
                        isSelected: viewModel.selectedTrackIndex == index,
                        isNowPlaying: viewModel.isPlaying && viewModel.selectedTrackIndex == index,
                        numberColumnWidth: numberColumnWidth
                    )
                    .id(index)
                    // `.simultaneousGesture` (not `.onTapGesture`) so this tap recognizer doesn't
                    // claim exclusive priority over the mouseDown/mouseDragged stream — exclusive
                    // claim is what prevented the List's native row-drag (`.onMove` below) from ever
                    // getting a chance to recognize a drag on macOS.
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
                        Button("Info", systemImage: "info.circle") {
                            infoTarget = file
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
                            get: { infoTarget?.id == file.id },
                            set: { if !$0 { infoTarget = nil } }
                        ),
                        arrowEdge: .trailing
                    ) {
                        TrackInfoCard(file: file)
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
            .onChange(of: viewModel.playlist.map(\.id)) { _, _ in
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
