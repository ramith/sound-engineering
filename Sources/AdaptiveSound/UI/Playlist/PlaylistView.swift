import SwiftUI

// MARK: - Playlist View

struct PlaylistView: View {
    @Environment(AudioViewModel.self) var viewModel
    @State private var showFolderPicker = false

    var body: some View {
        VStack(spacing: 12) {
            PlaylistHeaderView(showFolderPicker: $showFolderPicker)

            if !viewModel.folderPathDisplay.isEmpty {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.asLabelSecond)
                    Text(viewModel.folderPathDisplay)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.asLabelSecond)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.asCard)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
            }

            PlaylistItemList()
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let folderURL = urls.first {
                viewModel.musicFolderURL = folderURL
                Task {
                    // Hold the security-scoped access across the async enumeration —
                    // the previous `defer` released it before this Task ran, leaving
                    // a sandboxed build with an empty playlist.
                    let didAccess = folderURL.startAccessingSecurityScopedResource()
                    defer { if didAccess { folderURL.stopAccessingSecurityScopedResource() } }
                    await viewModel.loadMusicFolder(folderURL)
                }
            }
        }
    }
}

// MARK: - Playlist Header

private struct PlaylistHeaderView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Binding var showFolderPicker: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playlist")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.asLabelSecond)

                Text("\(viewModel.playlist.count) files · recursive")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.asLabelTertiary)
            }

            Spacer()

            PlaylistControlsView(showFolderPicker: $showFolderPicker)
        }
    }
}

// MARK: - Playlist Controls

private struct PlaylistControlsView: View {
    @Environment(AudioViewModel.self) var viewModel
    @Binding var showFolderPicker: Bool

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
                    // Scroll to current track (implemented via ScrollViewReader)
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 14))
                .foregroundStyle(Color.asAccent)
                .help("Jump to now playing")
            }

            Divider()
                .frame(height: 20)

            Button("Choose Folder…", systemImage: "folder") {
                showFolderPicker = true
            }
            .labelStyle(.titleAndIcon)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.asAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.asAccent.opacity(0.16))
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.asAccent.opacity(0.5), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Playlist Item List

private struct PlaylistItemList: View {
    @Environment(AudioViewModel.self) var viewModel

    /// Track-number column width sized to the widest index in the list (~8 pt per monospaced
    /// digit + slack), so a 190-track list reserves room for 3 digits and never wraps "191".
    private var numberColumnWidth: CGFloat {
        let digits = max(2, String(viewModel.playlist.count).count)
        return CGFloat(digits) * 8 + 6
    }

    var body: some View {
        List {
            ForEach(viewModel.playlist.enumerated(), id: \.element.id) { index, file in
                PlaylistItemRow(
                    file: file,
                    index: index,
                    isSelected: viewModel.selectedTrackIndex == index,
                    isNowPlaying: viewModel.isPlaying && viewModel.selectedTrackIndex == index,
                    numberColumnWidth: numberColumnWidth
                )
                .onTapGesture {
                    // Single-click plays the row, so the now-playing card always matches the
                    // audio (no select-without-play state). Re-clicking the track that's already
                    // playing is a no-op so it doesn't restart from the top.
                    guard !(viewModel.isPlaying && viewModel.selectedTrackIndex == index) else { return }
                    viewModel.playTrack(at: index)
                }
                .accessibilityAddTraits(.isButton)
                .contextMenu {
                    Button("Remove from Playlist", systemImage: "trash") {
                        viewModel.removeTrack(at: index)
                    }
                    Button("Clear Playlist", systemImage: "clear") {
                        viewModel.clearPlaylist()
                    }
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
                        if viewModel.isPlaying {
                            viewModel.stopPlayback()
                        } else {
                            viewModel.startPlayback()
                        }
                    }
                    return .handled
                }
                .onKeyPress(.space) {
                    if viewModel.selectedTrackIndex == index {
                        if viewModel.isPlaying {
                            viewModel.stopPlayback()
                        } else {
                            viewModel.startPlayback()
                        }
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
                viewModel.startPlayback()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.space) {
            if viewModel.selectedTrackIndex != nil {
                viewModel.startPlayback()
                return .handled
            }
            return .ignored
        }
    }
}
