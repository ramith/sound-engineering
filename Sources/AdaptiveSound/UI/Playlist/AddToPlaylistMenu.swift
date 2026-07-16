import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Add to Playlist (S10.3 US-PLIST-02 — context-menu submenu + searchable picker)

/// A reusable "Add to Playlist" submenu for a library-row context menu. Reference-adds the given
/// `trackIDs` (by id — NEVER a file move) via `PlaylistsModel`, with a confirmation toast. Inline:
/// New Playlist + the first few playlists; overflow routes to the searchable `PlaylistPickerSheet`
/// through `onChooseMore` (a context menu can't own a sheet — the host presents it).
struct AddToPlaylistMenu: View {
    let trackIDs: [Int64]
    /// Called when the user picks "Add to Playlist…" — the host opens `PlaylistPickerSheet`.
    let onChooseMore: () -> Void
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(LibraryBrowseModel.self) private var library

    /// How many playlists to show inline before deferring to the searchable sheet.
    private let inlineLimit = 6

    var body: some View {
        Menu("Add to Playlist") {
            Button("New Playlist") { Task { await createAndAdd() } }
            if !playlists.playlists.isEmpty {
                Divider()
                ForEach(playlists.playlists.prefix(inlineLimit)) { playlist in
                    Button(playlist.name) { Task { await add(to: playlist) } }
                }
                if playlists.playlists.count > inlineLimit {
                    Divider()
                    Button("Add to Playlist…") { onChooseMore() }
                }
            }
        }
        .disabled(trackIDs.isEmpty)
    }

    private func add(to playlist: Playlist) async {
        let added = await playlists.addTracks(trackIDs, toPlaylist: playlist.id)
        if let message = PlaylistAddDecision.toastMessage(added: added, playlistName: playlist.name) {
            library.showToast(message)
        }
    }

    private func createAndAdd() async {
        guard let id = await playlists.createPlaylist(withTracks: trackIDs) else { return }
        let name = playlists.playlists.first { $0.id == id }?.name ?? "New Playlist"
        let added = PlaylistAddDecision.trackIDsToAdd(trackIDs).count
        if let message = PlaylistAddDecision.toastMessage(added: added, playlistName: name) {
            library.showToast(message)
        }
    }
}

// MARK: - Picker sheet (scales past the inline submenu)

/// The `Identifiable` payload the host binds a `.sheet(item:)` to — the tracks awaiting a playlist
/// choice (UUID identity so re-triggering with the same tracks re-presents).
struct AddToPlaylistTarget: Identifiable {
    let id = UUID()
    let trackIDs: [Int64]
}

/// A searchable playlist picker (US-PLIST-02 "scales to hundreds"): filter with the shared
/// `LibraryFilterField`, tap a playlist to reference-add + dismiss. New Playlist is here too.
struct PlaylistPickerSheet: View {
    let trackIDs: [Int64]
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(LibraryBrowseModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private var filtered: [Playlist] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return playlists.playlists }
        return playlists.playlists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add to Playlist").font(DesignSystem.Font.sectionTitle)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(DesignSystem.Spacing.medium)

            LibraryFilterField(query: $filter, placeholder: "Filter playlists")
                .padding(.horizontal, DesignSystem.Spacing.medium)

            Button {
                Task { await createAndAdd() }
            } label: {
                Label("New Playlist", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(DesignSystem.Spacing.medium)

            Divider()

            List(filtered) { playlist in
                Button {
                    Task { await add(to: playlist); dismiss() }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "music.note.list")
                        Text(playlist.name).lineLimit(1)
                        Spacer()
                        Text(playlist.entryCount.formatted(.number))
                            .font(DesignSystem.Font.monoSmall)
                            .foregroundStyle(DesignSystem.Color.labelTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 380, height: 460)
    }

    private func add(to playlist: Playlist) async {
        let added = await playlists.addTracks(trackIDs, toPlaylist: playlist.id)
        if let message = PlaylistAddDecision.toastMessage(added: added, playlistName: playlist.name) {
            library.showToast(message)
        }
    }

    private func createAndAdd() async {
        guard let id = await playlists.createPlaylist(withTracks: trackIDs) else { return }
        let name = playlists.playlists.first { $0.id == id }?.name ?? "New Playlist"
        let added = PlaylistAddDecision.trackIDsToAdd(trackIDs).count
        if let message = PlaylistAddDecision.toastMessage(added: added, playlistName: name) {
            library.showToast(message)
        }
        dismiss()
    }
}
