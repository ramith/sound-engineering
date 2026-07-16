import LibraryStore
import SwiftUI

// MARK: - Album detail (S9.4)

/// Large-art header + metadata + visible Play / ⋯ actions, over a `List(selection:)` track
/// list in disc/track order. Row: double-click OR Return plays (single-click selects); the queue
/// verbs are exposed as named VoiceOver/keyboard actions as well as the context menu (S4 A-M4).
struct AlbumDetailView: View {
    let albumID: Int64

    @Environment(LibraryBrowseModel.self) private var model
    @State private var album: AlbumFacet?
    @State private var tracks: [LibraryTrackDisplay] = []
    @State private var selection = Set<LibraryTrackDisplay.ID>()
    /// The track whose info popover is open (mirrors the Now Playing playlist's Info affordance).
    @State private var infoTarget: LibraryTrackDisplay?
    /// Non-nil while the searchable "Add to Playlist…" picker is open (the host owns the sheet).
    @State private var addToPlaylistTarget: AddToPlaylistTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            backBar
            header
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            trackList
        }
        .task(id: albumID) {
            album = await model.album(id: albumID)
            tracks = await model.tracks(inAlbum: albumID)
        }
    }

    /// In-content back to the album grid. Replaces the `NavigationStack`'s window-toolbar back
    /// button, which is hidden along with the whole window toolbar under `.hiddenTitleBar` (L2).
    /// Pops the browse model's `path` (guarded — `removeLast()` on an empty array traps).
    private var backBar: some View {
        HStack {
            Button {
                if !model.path.isEmpty { model.path.removeLast() }
            } label: {
                Label("Library", systemImage: "chevron.backward")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DesignSystem.Color.accent)
            .accessibilityLabel("Back to Albums")
            .keyboardShortcut("[", modifiers: .command) // consistent with FacetTrackListView (S4 L7)

            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.top, DesignSystem.Spacing.small)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
            AlbumArtworkView(key: album?.artworkKey, side: 148, model: model)
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                Text(album?.title ?? "")
                    .font(DesignSystem.Font.displayTitle)
                    .foregroundStyle(DesignSystem.Color.label)
                Text(album?.albumArtist ?? "")
                    .font(DesignSystem.Font.sectionTitle)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                Text(subtitleLine)
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                actions.padding(.top, DesignSystem.Spacing.small)
            }
            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.medium)
    }

    private var actions: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Button {
                model.play(tracks, startAt: 0)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            // accentDeep, not accent: white-on-accent is only ~2.5:1 (below WCAG AA); the deeper
            // teal lifts it to ~4.3:1 (S4 A-M6). Final light-palette tuning is the founder make-run.
            .tint(DesignSystem.Color.accentDeep)
            .disabled(tracks.isEmpty)

            Menu {
                Button("Play Next") { model.playNext(tracks) }
                Button("Add to Queue") { model.append(tracks) }
                addToPlaylistMenu(trackIDs: tracks.map(\.id)) // whole album
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(tracks.isEmpty)
        }
    }

    private var trackList: some View {
        List(selection: $selection) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, leadingNumber: track.trackNo ?? (index + 1))
                    // Drag a track onto a sidebar playlist (US-PLIST-03) — reference-add by id, never
                    // a file move. A List row's drag SOURCE works (only its .dropDestination doesn't).
                    .draggable(LibraryTrackDragItem(trackID: track.id))
                    // `.simultaneousGesture` (not `.onTapGesture`) so the double-click recognizer
                    // doesn't claim exclusive priority over the List's selection gesture — the
                    // documented macOS drop-click race (S4 SW2; mirrors PlaylistItemList's rationale).
                    .simultaneousGesture(TapGesture(count: 2).onEnded { model.play(tracks, startAt: index) })
                    // Default action = Play (VoiceOver double-tap); the other verbs are named rotor
                    // actions so they're reachable without the mouse-only .contextMenu (S4 A-M4 —
                    // mirrors SongsTable). Return plays the selection (see `.onKeyPress` below).
                    .accessibilityAction { model.play(tracks, startAt: index) }
                    .accessibilityAction(named: "Play Next") { model.playNext([track]) }
                    .accessibilityAction(named: "Add to Queue") { model.append([track]) }
                    .accessibilityAction(named: "Info") { infoTarget = track }
                    .contextMenu {
                        Button("Play") { model.play(tracks, startAt: index) }
                        Button("Play Next") { model.playNext([track]) }
                        Button("Add to Queue") { model.append([track]) }
                        addToPlaylistMenu(trackIDs: [track.id])
                        Divider()
                        Button("Info", systemImage: "info.circle") { infoTarget = track }
                    }
                    .popover(
                        isPresented: Binding(
                            get: { infoTarget?.id == track.id },
                            set: { if !$0 { infoTarget = nil } }
                        ),
                        arrowEdge: .trailing
                    ) {
                        TrackInfoCard(file: AudioFile(track))
                    }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        // Keyboard play (S4 A-M4); `.ignored` on an empty selection so Return bubbles (focus-audit nit).
        .onKeyPress(.return) { selection.isEmpty ? .ignored : { playSelected(); return .handled }() }
        .sheet(item: $addToPlaylistTarget) { PlaylistPickerSheet(trackIDs: $0.trackIDs) }
    }

    /// The reference-add "Add to Playlist" submenu (S10.3); overflow opens the searchable picker.
    private func addToPlaylistMenu(trackIDs: [Int64]) -> some View {
        AddToPlaylistMenu(resolveTrackIDs: { trackIDs }, onChooseMore: { ids in
            addToPlaylistTarget = AddToPlaylistTarget(trackIDs: ids)
        })
    }

    /// Play the album starting at the selected row — the keyboard Return path (double-click is
    /// mouse-only in AppKit). Mirrors `FacetTrackListView.playSelected` (S4 A-M4).
    private func playSelected() {
        guard let id = selection.first, let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        model.play(tracks, startAt: index)
    }

    private var subtitleLine: String {
        var parts: [String] = []
        if let year = album?.year, year > 0 { parts.append("\(year)") }
        parts.append("\(tracks.count) song\(tracks.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}
