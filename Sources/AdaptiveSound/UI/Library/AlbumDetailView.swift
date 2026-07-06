import LibraryStore
import SwiftUI

// MARK: - Album detail (S9.4)

/// Large-art header + metadata + visible Play / ⋯ actions, over a `List(selection:)` track
/// list in disc/track order. Row: double-click / context-menu Play (single-click selects).
struct AlbumDetailView: View {
    let albumID: Int64

    @Environment(LibraryBrowseModel.self) private var model
    @State private var album: AlbumFacet?
    @State private var tracks: [LibraryTrackDisplay] = []
    @State private var selection = Set<LibraryTrackDisplay.ID>()
    /// The track whose info popover is open (mirrors the Now Playing playlist's Info affordance).
    @State private var infoTarget: LibraryTrackDisplay?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            trackList
        }
        .task(id: albumID) {
            album = await model.album(id: albumID)
            tracks = await model.tracks(inAlbum: albumID)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
            AlbumArtworkView(key: album?.artworkKey, side: 148)
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
            .tint(DesignSystem.Color.accent)
            .disabled(tracks.isEmpty)

            Menu {
                Button("Play Next") { model.playNext(tracks) }
                Button("Add to Queue") { model.append(tracks) }
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
                    .onTapGesture(count: 2) { model.play(tracks, startAt: index) }
                    // VoiceOver/keyboard activation mirrors the mouse double-click (review a11y):
                    // double-click is otherwise the only way to play a row.
                    .accessibilityAction { model.play(tracks, startAt: index) }
                    .contextMenu {
                        Button("Play") { model.play(tracks, startAt: index) }
                        Button("Play Next") { model.playNext([track]) }
                        Button("Add to Queue") { model.append([track]) }
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
    }

    private var subtitleLine: String {
        var parts: [String] = []
        if let year = album?.year, year > 0 { parts.append("\(year)") }
        parts.append("\(tracks.count) song\(tracks.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}
