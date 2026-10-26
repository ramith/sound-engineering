import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Add to Playlist (S10.3 US-PLIST-02 — context-menu submenu + searchable picker)

/// A reusable "Add to Playlist" submenu for any library context menu (Songs row, album/artist/genre
/// detail, AND the browse tiles). Reference-adds by track id — NEVER a file move. The ids are
/// resolved LAZILY (`resolveTrackIDs`, async) when an action fires, so a TILE can load its
/// album/facet tracks on demand while a detail row just returns its ids. Inline: New Playlist + the
/// first few playlists; the searchable-picker overflow shows only when `onChooseMore` is provided (a
/// context menu can't own a sheet — the host presents it; tile menus pass nil).
struct AddToPlaylistMenu: View {
    /// What the add holds, resolved when an item is chosen: library songs by id and — from the queue —
    /// files from outside the library (R1.1-B, US-PLIST-02).
    let resolveItems: () async -> [PlaylistAddItem]
    /// Called with the resolved ids when the user picks "Add to Playlist…"; nil (default, for tile
    /// menus with no sheet host) hides that item — inline playlists + New Playlist only.
    var onChooseMore: (([Int64]) -> Void)?

    /// The menu for library songs, by id.
    init(resolveTrackIDs: @escaping () async -> [Int64], onChooseMore: (([Int64]) -> Void)? = nil) {
        resolveItems = { await resolveTrackIDs().map(PlaylistAddItem.track) }
        self.onChooseMore = onChooseMore
    }

    /// The menu for library songs and loose files (the queue's rows); no "Add to Playlist…" picker.
    init(resolveItems: @escaping () async -> [PlaylistAddItem]) {
        self.resolveItems = resolveItems
    }

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
                if let onChooseMore, playlists.playlists.count > inlineLimit {
                    Divider()
                    Button("Add to Playlist…") { Task { onChooseMore(await Self.trackIDs(resolveItems())) } }
                }
            }
        }
    }

    private func add(to playlist: Playlist) async {
        let items = await resolveItems()
        let added = await playlists.add(items, toPlaylist: playlist.id)
        if let message = PlaylistAddDecision.toastMessage(added: added, playlistName: playlist.name) {
            library.showToast(message)
        }
    }

    private func createAndAdd() async {
        let items = await resolveItems()
        guard let created = await playlists.createPlaylist(with: items) else { return }
        let name = playlists.playlists.first { $0.id == created.id }?.name ?? "New Playlist"
        if let message = PlaylistAddDecision.toastMessage(added: created.added, playlistName: name) {
            library.showToast(message) // the songs that went in — fewer than chosen when a write failed (N3)
        }
    }
}

private extension AddToPlaylistMenu {
    /// The library songs' ids among `items` (the picker sheet adds songs by id).
    static func trackIDs(_ items: [PlaylistAddItem]) -> [Int64] {
        items.compactMap { item in
            if case let .track(id) = item {
                id
            } else {
                nil
            }
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
/// `FilterPill`, tap a playlist to reference-add + dismiss. New Playlist is here too. The sheet
/// itself stays system-drawn; only the filter inside it wears the app's pill (S10.8 D2).
struct PlaylistPickerSheet: View {
    let trackIDs: [Int64]
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(LibraryBrowseModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""
    /// The sheet's one focus value (`CardFocus`, K1): the pill (type-ready on open) is `.filter`,
    /// the playlist list `.content` — where Esc in the pill sends key focus.
    @FocusState private var focus: CardFocus?

    /// The playlists the filter keeps — by the Library's one search rule (R1.1-B), as ⌘F's Playlists.
    private var filtered: [Playlist] {
        FacetTextFilter.filter(playlists.playlists, query: filter, candidates: LibrarySearch.playlistKeys)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add to Playlist").font(DesignSystem.Font.sectionTitle)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(DesignSystem.Spacing.medium)

            FilterPill(text: $filter, prompt: "Filter playlists", focus: $focus,
                       focusShortcut: KeyboardShortcut("f"), focusesOnAppear: true)
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
            .focused($focus, equals: .content)
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
        guard let created = await playlists.createPlaylist(withTracks: trackIDs) else {
            dismiss() // a failure: the Library tab's notice says why, once this sheet is gone
            return
        }
        let name = playlists.playlists.first { $0.id == created.id }?.name ?? "New Playlist"
        if let message = PlaylistAddDecision.toastMessage(added: created.added, playlistName: name) {
            library.showToast(message) // the songs that went in (N3)
        }
        dismiss()
    }
}
