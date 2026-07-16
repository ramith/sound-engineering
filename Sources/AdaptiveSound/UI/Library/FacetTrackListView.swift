import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Facet track-list detail (S9.6 — shared by Artists / Genres / Years)

/// The flat song-list detail for a browse facet: a back bar + a header (title, "N songs ·
/// duration", Play + Shuffle + ⋯) over a `List(selection:)` of `TrackRow`. Two layouts:
///   • `groupByAlbum` (Artists) — songs under per-album `Section` headers (Apple-Music artist
///     page), with the leading track number correct WITHIN each album.
///   • flat (Genres / Years) — one list, no leading number, album shown on the row's secondary line.
/// Reuses the shipped `AlbumDetailView` interaction vocabulary (double-click / context-menu / Info
/// popover) but exposes the queue verbs as NAMED a11y actions (the album template exposes them only
/// in the context menu — VoiceOver-invisible). The album view is deliberately NOT refactored onto
/// this (gate R2): this is new, facet-only.
struct FacetTrackListView: View {
    let title: String
    /// The pop-target label for VoiceOver ("Back to Artists" / "Genres" / "Years").
    let backLabel: String
    let tracks: [LibraryTrackDisplay]
    /// Artists group by album (`Section` per album); Genres / Years stay flat.
    let groupByAlbum: Bool

    @Environment(LibraryBrowseModel.self) private var model
    @State private var selection = Set<LibraryTrackDisplay.ID>()
    @State private var infoTarget: LibraryTrackDisplay?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            backBar
            header
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            switch FacetDetailState.state(trackCount: tracks.count) {
            case .empty:
                // A reachable-but-empty facet (e.g. one whose songs dropped to 0 after a rescan).
                ContentUnavailableView("No Songs", systemImage: "music.note")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .list:
                if groupByAlbum { groupedList } else { flatList }
            }
        }
    }

    // MARK: Back bar (⌘[ / in-content — the window toolbar is hidden under the custom chrome)

    private var backBar: some View {
        HStack {
            Button { goBack() } label: {
                Label("Library", systemImage: "chevron.backward")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DesignSystem.Color.accent)
            .accessibilityLabel(backLabel)
            .keyboardShortcut("[", modifiers: .command)
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.top, DesignSystem.Spacing.small)
    }

    private func goBack() {
        if !model.path.isEmpty { model.path.removeLast() }
    }

    // MARK: Header (title · subtitle · Play + Shuffle + ⋯)

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
            Text(title)
                .font(DesignSystem.Font.displayTitle)
                .foregroundStyle(DesignSystem.Color.label)
                .lineLimit(1)
            Text(subtitle)
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
            actions.padding(.top, DesignSystem.Spacing.small)
        }
        .padding(DesignSystem.Spacing.medium)
    }

    private var subtitle: String {
        let seconds = tracks.reduce(0.0) { $0 + $1.durationSeconds }
        return "\(FacetCountLabel.songs(count: tracks.count)) · \(humaneTotalDuration(seconds))"
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

            Button {
                model.shuffle(tracks)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(.bordered)
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

    // MARK: Lists

    private var flatList: some View {
        List(selection: $selection) {
            ForEach(tracks) { track in
                row(for: track, leadingNumber: nil, secondary: secondaryLine(track))
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .onKeyPress(.return) { selection.isEmpty ? .ignored : { playSelected(); return .handled }() }
    }

    private var groupedList: some View {
        List(selection: $selection) {
            ForEach(FacetAlbumGrouping.sections(from: tracks)) { section in
                Section {
                    ForEach(section.tracks) { track in
                        row(for: track, leadingNumber: track.trackNo, secondary: "")
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .onKeyPress(.return) { selection.isEmpty ? .ignored : { playSelected(); return .handled }() }
    }

    private func sectionHeader(_ section: FacetAlbumSection<LibraryTrackDisplay>) -> some View {
        HStack(spacing: DesignSystem.Spacing.xSmall) {
            Text(section.title)
                .font(DesignSystem.Font.sectionTitle)
                .foregroundStyle(DesignSystem.Color.label)
            if let year = section.year {
                Text("· \(year)") // a bare year — never thousands-grouped
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: One row (double-click / Return / named a11y actions / context menu / Info popover)

    private func row(for track: LibraryTrackDisplay, leadingNumber: Int?, secondary: String) -> some View {
        TrackRow(track: track, leadingNumber: leadingNumber, secondary: secondary)
            // Drag a track onto a sidebar playlist (US-PLIST-03) — reference-add by id, never a file
            // move. A List row's drag SOURCE works (only its .dropDestination doesn't).
            .draggable(LibraryTrackDragItem(trackID: track.id))
            // `.simultaneousGesture` (not `.onTapGesture`) so the double-click recognizer doesn't
            // claim exclusive priority over the List's selection gesture — the documented macOS
            // drop-click race (S4 SW2; mirrors PlaylistItemList's rationale).
            .simultaneousGesture(TapGesture(count: 2).onEnded { playFromRow(track) })
            // Named actions so VoiceOver/keyboard reach every verb (the album template exposes these
            // only in .contextMenu, which the rotor can't see — swiftui review #2).
            .accessibilityAction(named: "Play") { playFromRow(track) }
            .accessibilityAction(named: "Play Next") { model.playNext([track]) }
            .accessibilityAction(named: "Add to Queue") { model.append([track]) }
            .accessibilityAction(named: "Info") { infoTarget = track }
            .contextMenu {
                Button("Play") { playFromRow(track) }
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

    /// Genres/Years flat rows show "Artist · Album" (the Songs-tab secondary convention).
    private func secondaryLine(_ track: LibraryTrackDisplay) -> String {
        [track.artistName, track.albumName ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Play the whole facet starting at `track` (index resolved on click only — never per-frame).
    private func playFromRow(_ track: LibraryTrackDisplay) {
        model.play(tracks, startAt: tracks.firstIndex(where: { $0.id == track.id }) ?? 0)
    }

    private func playSelected() {
        guard let id = selection.first, let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        model.play(tracks, startAt: index)
    }
}
