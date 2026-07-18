import LibraryBrowseKit
import LibraryStore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library sidebar (S9.4 + S9 IA Music Folders footer + S10.3 Playlists section)

/// The browse categories PLUS a dedicated Playlists section, over a pinned Music Folders footer.
///
/// ★ S10.3 rebuild (design §1): the whole list is ONE `ScrollView { LazyVStack }` of plain `Button`
/// rows with a single `SidebarSelection` — NOT `List(selection:)`. A `List` row's `.dropDestination`
/// never fires (needed for drag-to-playlist in Chunk E) and `List(selection:)` races custom row
/// gestures + double-highlights against a second selection system. Selection lives on the injected
/// `LibraryBrowseModel` (survives the tab-switch teardown); the capsule is `Color.rowSelected`. ↑/↓
/// walk the unified row order via `.onKeyPress` + `@FocusState` (the `List` freebie, re-created).
struct LibrarySidebar: View {
    // `internal` (not `private`) so the same-type `LibrarySidebar+Rename` extension (split out for
    // file/type-body length) can reach them — an extension of this type IS this type.
    @Environment(LibraryBrowseModel.self) var model
    @Environment(PlaylistsModel.self) var playlists
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFolderImporter = false

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

    /// Music Folders accordion expand/collapse — persisted across launches and view recreation
    /// (design §8), matching the `.v1`-key `@AppStorage` convention `EQTabView` uses.
    @AppStorage("library.foldersExpanded.v1") private var isFoldersExpanded = false

    /// The unified top-to-bottom row order for ↑/↓ navigation (categories, then playlists). Chunk D
    /// inserts folder nodes here; the enum gains no cases (a folder is a container, not a selection).
    private var selectables: [SidebarSelection] {
        LibraryCategory.allCases.map(SidebarSelection.category)
            + playlists.playlists.map { SidebarSelection.playlist($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(LibraryCategory.allCases) { category in
                        categoryRow(category)
                    }
                    playlistsSectionHeader
                    playlistRows
                }
                .padding(.horizontal, DesignSystem.Spacing.small)
                .padding(.vertical, DesignSystem.Spacing.xSmall)
            }
            .focusable()
            .focused($sidebarFocused)
            .defaultFocus($sidebarFocused, true)
            .focusEffectDisabled()
            // ↑/↓/Return stand down WHILE a rename field is open — otherwise this ScrollView (still
            // in the focus chain) HIJACKS the keys from the focused TextField: Return hit
            // `renameSelectedPlaylist` (re-entrant `beginRename` → wiped the typed draft) instead of
            // the field's `onSubmit`, and arrows moved the sidebar selection instead of the cursor.
            .onKeyPress(.upArrow) { editingPlaylistID == nil ? moveSelection(by: -1) : .ignored }
            .onKeyPress(.downArrow) { editingPlaylistID == nil ? moveSelection(by: 1) : .ignored }
            // Return renames the selected playlist (Finder/Music convention + keyboard discoverability
            // for an action otherwise only in the right-click menu). Categories ignore it (bubbles).
            .onKeyPress(.return) { editingPlaylistID == nil ? renameSelectedPlaylist() : .ignored }
        }
        // A sidebar material so the column reads as a source list now that `.listStyle(.sidebar)` is
        // gone (the plain ScrollView doesn't imply it).
        // nosemgrep: ui-no-adhoc-material TEMP reason="Glass-token adoption = S10.8 sweep" expiry=2026-08-15
        .background(.bar)
        .safeAreaInset(edge: .bottom) { footer }
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { model.addFolder(url) }
        }
        .task { await playlists.loadTree() }
        // Load the tree once the async store finishes building (a visit before then shows nothing).
        .onChange(of: playlists.isStoreReady) { _, ready in
            if ready { Task { await playlists.loadTree() } }
        }
    }

    // MARK: - Category rows

    private func categoryRow(_ category: LibraryCategory) -> some View {
        let isSelected = model.sidebarSelection == .category(category)
        return Button {
            model.selectCategory(category)
            sidebarFocused = true
        } label: {
            rowLabel(isSelected: isSelected) {
                Label(category.title, systemImage: category.icon)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playlists section

    private var playlistsSectionHeader: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Text("Playlists")
                .font(DesignSystem.Font.micro)
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
            Spacer(minLength: 0)
            Button {
                Task { await createAndBeginRename() }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DesignSystem.Color.accent)
            .disabled(!playlists.isStoreReady)
            .help("New Playlist")
            .accessibilityLabel("New Playlist")
        }
        .padding(.horizontal, DesignSystem.Spacing.small)
        .padding(.top, DesignSystem.Spacing.medium)
        .padding(.bottom, DesignSystem.Spacing.xSmall)
    }

    @ViewBuilder private var playlistRows: some View {
        if playlists.playlists.isEmpty {
            Text("No playlists yet")
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .padding(.horizontal, DesignSystem.Spacing.small)
                .padding(.vertical, DesignSystem.Spacing.xSmall)
        } else {
            ForEach(playlists.playlists) { playlist in
                playlistRow(playlist)
            }
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        if editingPlaylistID == playlist.id {
            renameField(playlist)
        } else {
            let isSelected = model.sidebarSelection == .playlist(playlist.id)
            Button {
                model.selectPlaylist(playlist.id)
                sidebarFocused = true
            } label: {
                rowLabel(isSelected: isSelected) {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "music.note.list")
                        Text(playlist.name).lineLimit(1)
                        Spacer(minLength: DesignSystem.Spacing.small)
                        Text(playlist.entryCount.formatted(.number))
                            .font(DesignSystem.Font.monoSmall)
                            .foregroundStyle(DesignSystem.Color.labelTertiary)
                    }
                }
                .overlay( // drop-target ring while a library track is dragged over this row
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                        .stroke(DesignSystem.Color.accent,
                                lineWidth: dropTargetPlaylistID == playlist.id ? 1.5 : 0)
                )
            }
            .buttonStyle(.plain)
            // Drop a dragged library track (US-PLIST-03) → reference-ADD by id (PlaylistDropRouter is
            // add-only by construction; no file move/copy). A file-URL/audio drag can't match the
            // `LibraryTrackDragItem` type, so it never reaches here.
            .dropDestination(for: LibraryTrackDragItem.self) { items, _ in
                handleTrackDrop(items, onto: playlist)
            } isTargeted: { targeted in
                dropTargetPlaylistID = targeted ? playlist.id
                    : (dropTargetPlaylistID == playlist.id ? nil : dropTargetPlaylistID)
            }
            // Double-click to rename (Finder/Music convention) — the discoverable gesture alongside
            // the context-menu Rename + the Return key. `.simultaneousGesture` so it coexists with
            // the Button's single-click select (plain Buttons in a LazyVStack, not a List — no race).
            .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename(playlist) })
            .contextMenu {
                Button("Rename") { beginRename(playlist) }
                Button("Delete", role: .destructive) { deletePlaylist(playlist) }
            }
        }
    }

    private func renameField(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Playlist name", text: $editDraft)
                .textFieldStyle(.plain)
                .font(DesignSystem.Font.body)
                // Applies `.focused($renameFieldFocused)` AND the transport-Space gate in one place.
                .suppressesTransportSpace(while: $renameFieldFocused)
                // Click-away COMMITS (Finder/Music convention — silent revert is surprising data
                // loss). Guarded on `wasFocused` so the deferred-focus arrival (false→true) can't
                // self-commit, and on `editingPlaylistID` so a post-teardown blur is a no-op.
                // Escape (`.onExitCommand`) is the sole cancel and niles `editingPlaylistID` first,
                // so a blur it triggers is guarded out (no commit-on-Escape).
                .onChange(of: renameFieldFocused) { wasFocused, isFocused in
                    if wasFocused, !isFocused, editingPlaylistID == playlist.id {
                        commitRename(playlist, proposed: editDraft, keepOpenOnConflict: false)
                    }
                }
                // Focus HERE, in the field's own onAppear — reliable post-insertion (the field is in
                // the hierarchy), unlike a @FocusState set from beginRename which bounced on a
                // freshly-inserted LazyVStack row and let the blur handler self-close the field.
                .onAppear { renameFieldFocused = true }
                // Capture the draft SYNCHRONOUSLY at submit: a later blur/teardown that clears
                // `editDraft` must not race the async rename into an empty/stale name.
                .onSubmit { commitRename(playlist, proposed: editDraft, keepOpenOnConflict: true) }
                .onExitCommand {
                    cancelRename()
                    sidebarFocused = true // keyboard close → keep ↑/↓/Return alive (focus-audit MAJOR)
                }
                .padding(.horizontal, DesignSystem.Spacing.small)
                .padding(.vertical, 5)
            if let renameError {
                Text(renameError)
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.statusErrorText)
                    .padding(.horizontal, DesignSystem.Spacing.small)
            }
        }
    }

    // MARK: - Row chrome

    /// The shared row capsule: selection tint + accent-on-selected label color, consistent leading
    /// inset. Content is a `Label`/`HStack` supplied by the caller.
    private func rowLabel(isSelected: Bool, @ViewBuilder content: () -> some View) -> some View {
        content()
            .font(DesignSystem.Font.body)
            .foregroundStyle(isSelected ? DesignSystem.Color.accent : DesignSystem.Color.label)
            .padding(.horizontal, DesignSystem.Spacing.small)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? DesignSystem.Color.rowSelected : Color.clear,
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
            )
            .contentShape(Rectangle())
            // Selection is conveyed by color alone otherwise — expose it to VoiceOver (matching
            // `PlaylistItemRow`); `.combine` folds a trailing count into the one row element.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            if deleted, wasSelected { model.selectCategory(model.selectedCategory ?? .songs) }
        }
    }

    /// Move the unified selection by `delta` rows through `selectables` (keyboard ↑/↓). `.ignored`
    /// when the move would leave the list, so the event can bubble. Also `.ignored` while a browse
    /// drill-down (album/artist/genre detail) is showing: `sidebarSelection` collapses that to its
    /// category, so an arrow press would otherwise navigate away and DESTROY the drill-down.
    private func moveSelection(by delta: Int) -> KeyPress.Result {
        if let route = model.path.last {
            switch route {
            case .album, .artist, .genre: return .ignored // a drill-down is open — don't blow it away
            case .playlist: break // a playlist is selected — arrow nav among rows is fine
            }
        }
        let items = selectables
        guard let current = items.firstIndex(of: model.sidebarSelection) else { return .ignored }
        let next = current + delta
        guard next >= 0, next < items.count else { return .ignored }
        switch items[next] {
        case let .category(category): model.selectCategory(category)
        case let .playlist(id): model.selectPlaylist(id)
        }
        return .handled
    }
}

// MARK: - Music Folders footer (S9 IA change — unchanged)

/// Split into a same-type extension to keep the primary `LibrarySidebar` body under the
/// type-body-length limit (same pattern as `LibraryBrowseModel+Facets`).
private extension LibrarySidebar {
    var footer: some View {
        VStack(spacing: 0) {
            if let status = model.scanStatusText {
                HStack(spacing: DesignSystem.Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(DesignSystem.Font.caption)
                        .foregroundStyle(DesignSystem.Color.labelSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.vertical, DesignSystem.Spacing.small)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            }
            HStack(spacing: DesignSystem.Spacing.small) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        isFoldersExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "chevron.forward")
                            .rotationEffect(.degrees(isFoldersExpanded ? 90 : 0))
                            .accessibilityHidden(true)
                        Image(systemName: "folder")
                            .accessibilityHidden(true)
                        Text("Music Folders")
                    }
                    .font(DesignSystem.Font.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
                .accessibilityValue(isFoldersExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Show or hide your music folders.")
                Spacer(minLength: 0)
                Button("Add Music Folder", systemImage: "plus") { showFolderImporter = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(DesignSystem.Color.accent)
                    .disabled(!model.isStoreReady)
                    .help("Add a music folder")
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            if isFoldersExpanded {
                VStack(spacing: 0) {
                    Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
                    MusicFoldersAccordionContent()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // nosemgrep: ui-no-adhoc-material TEMP reason="Glass-token adoption = S10.8 sweep" expiry=2026-08-15
        .background(.bar)
    }
}
