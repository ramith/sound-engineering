import LibraryBrowseKit
import LibraryStore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library sidebar (S9.4 + S9 IA Music Folders + S10.3 Playlists + S10.8 Twin Panels rail)

/// The browse categories, a Playlists section, and a Music Folders section — as a single FLOATING
/// GLASS CARD (`png/01`), content-height at the top of the rail column so the shared teal glow
/// shows below it.
///
/// ★ S10.3 rebuild (design §1): the whole list is ONE `ScrollView { LazyVStack }` of plain `Button`
/// rows with a single `SidebarSelection` — NOT `List(selection:)`. A `List` row's `.dropDestination`
/// never fires (needed for drag-to-playlist) and `List(selection:)` races custom row gestures +
/// double-highlights against a second selection system. Selection lives on the injected
/// `LibraryBrowseModel` (survives the tab-switch teardown). ↑/↓ walk the unified row order via
/// `.onKeyPress` + `@FocusState` (the `List` freebie, re-created).
///
/// ★ S10.8 PR-C: the rail is now `.huggingGlassPanel` (the shared NP-inspector card — content-height,
/// scroll when the window is short). Music Folders moved from the pinned `safeAreaInset` footer to an
/// inline section (the mock shows folders inline; the collapse accordion is retired — the
/// content-height card + scroll handle overflow, and folder add/remove/scan-hint are preserved).
struct LibrarySidebar: View {
    // `internal` (not `private`) so the same-type `LibrarySidebar+Rename` extension (split out for
    // file/type-body length) can reach them — an extension of this type IS this type.
    @Environment(LibraryBrowseModel.self) var model
    @Environment(PlaylistsModel.self) var playlists
    @State private var showFolderImporter = false

    /// Measured height of the card content — the floating card HUGS this instead of stretching to
    /// the column bottom; a short window lets the inner ScrollView scroll (NP inspector E1 pattern).
    /// Zero = "not yet measured" → fill for one layout pass.
    @State private var contentHeight: CGFloat = 0

    // Inline-rename state (design §4: editing id in parent @State). `editDraft` is the field text;
    // `renameError` shows an inline conflict message and keeps the field open.
    @State var editingPlaylistID: Int64?
    @State var editDraft = ""
    @State var renameError: String?
    /// The playlist row a library-track drag is hovering over (drop highlight), or nil.
    @State private var dropTargetPlaylistID: Int64?
    @FocusState var renameFieldFocused: Bool

    /// Keyboard-command focus for the scroll area (a ScrollView/LazyVStack doesn't own key focus the
    /// way a `List` does — same `.focusable`/`.focused`/`.defaultFocus` pattern the queue uses).
    /// `internal` for the same-type `LibrarySidebar+Rename` extension (focus yield/restore).
    @FocusState var sidebarFocused: Bool
    /// Draw the cursor ring only while the user navigates by keyboard (A-review).
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus

    var body: some View {
        ScrollViewReader { proxy in
            let ringRow = ringCursorRow
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(LibraryCategory.allCases) { category in
                        categoryRow(category, isKeyboardCursor: ringRow == .category(category))
                    }
                    sectionDivider
                    playlistsSectionHeader
                    playlistRows(ringRow: ringRow)
                    sectionDivider
                    musicFoldersSectionHeader
                    MusicFoldersSection()
                    scanStatusStrip
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                // The guide's rail inset (PR-C "inner padding 12×10"; png/00 measures 10pt under
                // the last row). It was the 24pt bleed run while the card carried a bottom bleed
                // that text had to stay off; the card is flat now, so the rail ends where the
                // mock's does.
                .padding(.bottom, 10)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    contentHeight = height
                }
            }
            .focusable()
            .focused($sidebarFocused)
            .defaultFocus($sidebarFocused, true)
            // The system effect would outline the whole rail; the cursor row's ring replaces it (A3).
            // Always focusable — the category rows never empty out.
            .focusEffectDisabled()
            // ↑/↓/Return stand down WHILE a rename field is open — otherwise this ScrollView (still
            // in the focus chain) HIJACKS the keys from the focused TextField (arrows moved the
            // sidebar selection instead of the cursor; Return re-entered `beginRename`).
            .onKeyPress(.upArrow) { editingPlaylistID == nil ? moveSelection(by: -1, proxy: proxy) : .ignored }
            .onKeyPress(.downArrow) { editingPlaylistID == nil ? moveSelection(by: 1, proxy: proxy) : .ignored }
            // Return renames the selected playlist (Finder/Music convention). Categories ignore it.
            .onKeyPress(.return) { editingPlaylistID == nil ? renameCursorPlaylist() : .ignored }
        }
        // Content-height floating glass card (shared with the NP inspector via `.huggingGlassPanel`):
        // hug the measured content, scroll when the window is short. The shared teal glow (PR-B) sits
        // behind both cards at the window level, so there is no per-card glow here.
        .huggingGlassPanel(contentHeight: contentHeight)
        .frame(width: DesignSystem.LayoutMetrics.sidebarIdeal)
        .frame(maxHeight: .infinity, alignment: .top)
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                model.addFolder(url)
            }
        }
        .task { await playlists.loadTree() }
        // Load the tree once the async store finishes building (a visit before then shows nothing).
        .onChange(of: playlists.isStoreReady) { _, ready in
            if ready {
                Task { await playlists.loadTree() }
            }
        }
    }

    // MARK: - Category rows

    private func categoryRow(_ category: LibraryCategory, isKeyboardCursor: Bool) -> some View {
        let isSelected = model.sidebarSelection == .category(category)
        return Button {
            model.selectCategory(category)
            sidebarFocused = true
        } label: {
            NavRow(icon: category.icon, label: category.title, active: isSelected,
                   isKeyboardCursor: isKeyboardCursor)
        }
        .buttonStyle(.plain)
        // Selection is conveyed by color alone otherwise — expose it to VoiceOver; `.combine`
        // folds the row into one activatable element carrying the `.isSelected` trait.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(SidebarSelection.category(category)) // the arrow keys' `scrollTo` target (A3)
    }

    // MARK: - Playlists section

    private var playlistsSectionHeader: some View {
        NavSectionHeader(title: "Playlists", addHelp: "New Playlist",
                         addDisabled: !playlists.isStoreReady) {
            Task { await createAndBeginRename() }
        }
    }

    @ViewBuilder
    private func playlistRows(ringRow: SidebarSelection?) -> some View {
        if playlists.playlists.isEmpty {
            Text("No playlists yet")
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
                .padding(.vertical, DesignSystem.Spacing.xSmall)
        } else {
            ForEach(playlists.playlists) { playlist in
                playlistRow(playlist, isKeyboardCursor: ringRow == .playlist(playlist.id))
            }
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist, isKeyboardCursor: Bool) -> some View {
        if editingPlaylistID == playlist.id {
            renameField(playlist)
        } else {
            let isSelected = model.sidebarSelection == .playlist(playlist.id)
            Button {
                model.selectPlaylist(playlist.id)
                sidebarFocused = true
            } label: {
                NavRow(icon: "music.note.list", label: playlist.name, active: isSelected,
                       isKeyboardCursor: isKeyboardCursor) {
                    Text(playlist.entryCount.formatted(.number))
                        .font(DesignSystem.Font.monoSmall)
                        .foregroundStyle(DesignSystem.Color.labelTertiary)
                }
                .overlay( // drop-target ring while a library track is dragged over this row
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.container)
                        .stroke(DesignSystem.Color.accent,
                                lineWidth: dropTargetPlaylistID == playlist.id ? 1.5 : 0)
                )
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            // Drop a dragged library track (US-PLIST-03) → reference-ADD by id (PlaylistDropRouter is
            // add-only by construction; no file move/copy). A file-URL/audio drag can't match the
            // `LibraryTrackDragItem` type, so it never reaches here.
            .dropDestination(for: LibraryTrackDragItem.self) { items, _ in
                handleTrackDrop(items, onto: playlist)
            } isTargeted: { targeted in
                dropTargetPlaylistID = targeted ? playlist.id
                    : (dropTargetPlaylistID == playlist.id ? nil : dropTargetPlaylistID)
            }
            // Double-click to rename (Finder/Music convention). `.simultaneousGesture` so it coexists
            // with the Button's single-click select (plain Buttons in a LazyVStack).
            .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename(playlist) })
            .contextMenu {
                Button("Rename") { beginRename(playlist) }
                Button("Delete", role: .destructive) { deletePlaylist(playlist) }
            }
            .id(SidebarSelection.playlist(playlist.id)) // the arrow keys' `scrollTo` target (A3)
        }
    }

    private func renameField(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Playlist name", text: $editDraft)
                .textFieldStyle(.plain)
                .font(DesignSystem.Font.body)
                // Applies `.focused($renameFieldFocused)` AND the transport-Space gate in one place.
                .suppressesTransportSpace(while: $renameFieldFocused)
                // Click-away COMMITS (Finder/Music convention). Guarded on `wasFocused` so the
                // deferred-focus arrival (false→true) can't self-commit, and on `editingPlaylistID`
                // so a post-teardown blur is a no-op. Escape (`.onExitCommand`) is the sole cancel.
                .onChange(of: renameFieldFocused) { wasFocused, isFocused in
                    if wasFocused, !isFocused, editingPlaylistID == playlist.id {
                        commitRename(playlist, proposed: editDraft, keepOpenOnConflict: false)
                    }
                }
                // Focus HERE, in the field's own onAppear — reliable post-insertion, unlike a
                // @FocusState set from beginRename which bounced on a freshly-inserted row.
                .onAppear { renameFieldFocused = true }
                // Capture the draft SYNCHRONOUSLY at submit: a later blur/teardown that clears
                // `editDraft` must not race the async rename into an empty/stale name.
                .onSubmit { commitRename(playlist, proposed: editDraft, keepOpenOnConflict: true) }
                .onExitCommand {
                    cancelRename()
                    sidebarFocused = true // keyboard close → keep ↑/↓/Return alive (focus-audit MAJOR)
                }
                .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
                .padding(.vertical, 5)
            if let renameError {
                Text(renameError)
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.statusErrorText)
                    .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
            }
        }
    }

    // MARK: - Music Folders section (S10.8: inline, replacing the pinned footer accordion)

    private var musicFoldersSectionHeader: some View {
        NavSectionHeader(title: "Music Folders", icon: "folder", addHelp: "Add a music folder",
                         addDisabled: !model.isStoreReady) {
            showFolderImporter = true
        }
    }

    /// The transient library-scan progress strip (was the footer's top row) — now the last item in
    /// the card content. Only present while a scan reports status.
    @ViewBuilder private var scanStatusStrip: some View {
        if let status = model.scanStatusText {
            HStack(spacing: DesignSystem.Spacing.small) {
                ProgressView().controlSize(.small)
                Text(status)
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
            .padding(.top, DesignSystem.Spacing.small)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// A 1px hairline run separating rail sections (mock: `white 7%`, inset).
    private var sectionDivider: some View {
        Rectangle()
            .fill(DesignSystem.Color.hairline)
            .frame(height: 1)
            .padding(.horizontal, DesignSystem.Spacing.small)
            .padding(.vertical, 6)
    }

    // MARK: - Actions

    /// Reference-add dropped library tracks to `playlist` (US-PLIST-03/04). Routes through the
    /// add-only `PlaylistDropRouter` (no file op is representable), then confirms with a toast.
    private func handleTrackDrop(_ items: [LibraryTrackDragItem], onto playlist: Playlist) -> Bool {
        dropTargetPlaylistID = nil
        guard case let .addTracks(ids) = PlaylistDropRouter.route(droppedTrackIDs: items.map(\.trackID)),
              !ids.isEmpty else { return false }
        Task {
            let added = await playlists.addTracks(ids, toPlaylist: playlist.id)
            if let message = PlaylistAddDecision.toastMessage(added: added, playlistName: playlist.name) {
                model.showToast(message)
            }
        }
        return true
    }

    /// Delete a playlist; if it was the open/selected one, redirect nav back to the current category
    /// so the detail pane doesn't orphan on a `.playlist(deletedID)` route that resolves to nothing.
    /// Only redirects on a CONFIRMED delete — a failed delete leaves the row, so nav must stay put.
    private func deletePlaylist(_ playlist: Playlist) {
        let wasSelected = model.sidebarSelection == .playlist(playlist.id)
        Task {
            let deleted = await playlists.deletePlaylist(id: playlist.id)
            if deleted, wasSelected {
                model.selectCategory(model.selectedCategory ?? .songs)
            }
        }
    }
}

// MARK: - Keyboard cursor (↑/↓)

/// Same-file extension (type-body length): reaches the rail's private state.
private extension LibrarySidebar {
    /// The unified top-to-bottom row order for ↑/↓ navigation (categories, then playlists).
    var selectables: [SidebarSelection] {
        LibraryCategory.allCases.map(SidebarSelection.category)
            + playlists.playlists.map { SidebarSelection.playlist($0.id) }
    }

    /// A browse drill-down (album/artist/genre detail) is showing. `sidebarSelection` collapses it
    /// to its category, so an arrow press would navigate away and DESTROY the drill-down — the
    /// keys stand down there. (An open playlist is a rail row itself: arrows stay live.)
    var isBrowseDrillDownOpen: Bool {
        switch model.path.last {
        case .album, .artist, .genre: true
        case .playlist, nil: false
        }
    }

    /// The ONE keyboard cursor (A3, A-review) — the ring row, the row ↑/↓ move from and the row
    /// Return renames: the rail selection. Nil while a drill-down is open, where the keys stand
    /// down — so the ring hides with them instead of promising a move that won't happen.
    var keyboardCursor: ListKeyboardCursor<SidebarSelection>? {
        guard !isBrowseDrillDownOpen else { return nil }
        return ListKeyboardCursor.resolve(rows: selectables, anchor: model.sidebarSelection)
    }

    /// The ring is drawn while the rail holds key focus AND the user navigates by keyboard.
    var showsRing: Bool {
        sidebarFocused && showsKeyboardFocus
    }

    /// The row wearing the focus ring, or nil (no ring).
    var ringCursorRow: SidebarSelection? {
        showsRing ? keyboardCursor?.id : nil
    }

    /// Move the rail selection from the cursor by `delta` rows through `selectables` (keyboard
    /// ↑/↓). `.ignored` when the move would leave the list or a drill-down is open, so the event
    /// can bubble. Keeps the new selection on screen the queue's way (A3) — the rail scrolls when
    /// the window is short: `scrollTo` with no anchor scrolls only as far as needed, instantly.
    func moveSelection(by delta: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let target = keyboardCursor?.step(by: delta, in: selectables) else { return .ignored }
        switch target {
        case let .category(category): model.selectCategory(category)
        case let .playlist(id): model.selectPlaylist(id)
        }
        proxy.scrollTo(target)
        return .handled
    }

    /// Return: rename the cursor row when it is a playlist (Finder/Music convention). `.ignored`
    /// for a category or an open drill-down, so the event bubbles.
    func renameCursorPlaylist() -> KeyPress.Result {
        guard case let .playlist(id) = keyboardCursor?.actionTarget(ringVisible: showsRing),
              let playlist = playlists.playlists.first(where: { $0.id == id }) else { return .ignored }
        beginRename(playlist)
        return .handled
    }
}
