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
    @Environment(LibraryBrowseModel.self) private var model
    @Environment(PlaylistsModel.self) private var playlists
    /// Suppresses the global Space accelerator while the inline-rename field is focused (S4 SW1).
    @Environment(KeyboardTransportFocus.self) private var keyboardFocus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFolderImporter = false

    // Inline-rename state (design §4: editing id in parent @State). `editDraft` is the field text;
    // `renameError` shows an inline conflict message and keeps the field open.
    @State private var editingPlaylistID: Int64?
    @State private var editDraft = ""
    @State private var renameError: String?
    @FocusState private var renameFieldFocused: Bool

    /// Keyboard-command focus for the scroll area (a ScrollView/LazyVStack doesn't own key focus the
    /// way a `List` does — same `.focusable`/`.focused`/`.defaultFocus` pattern the queue uses).
    @FocusState private var sidebarFocused: Bool

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
            .onKeyPress(.upArrow) { moveSelection(by: -1) }
            .onKeyPress(.downArrow) { moveSelection(by: 1) }
            // Return renames the selected playlist (Finder/Music convention + keyboard discoverability
            // for an action otherwise only in the right-click menu). Categories ignore it (bubbles).
            .onKeyPress(.return) { renameSelectedPlaylist() }
        }
        // A sidebar material so the column reads as a source list now that `.listStyle(.sidebar)` is
        // gone (the plain ScrollView doesn't imply it).
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
            }
            .buttonStyle(.plain)
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
                .focused($renameFieldFocused)
                // Suppress the global Space accelerator while editing (S4 SW1) — the same inline
                // trio `LibraryFilterField`/`SongsHeader` use; Chunk E extracts it to a modifier.
                // Click-away COMMITS (Finder/Music convention — silent revert is surprising data
                // loss). Guarded on `wasFocused` so the deferred-focus arrival (false→true) can't
                // self-commit, and on `editingPlaylistID` so a post-teardown blur is a no-op.
                // Escape (`.onExitCommand`) is the sole cancel and niles `editingPlaylistID` first,
                // so a blur it triggers is guarded out (no commit-on-Escape).
                .onChange(of: renameFieldFocused) { wasFocused, isFocused in
                    keyboardFocus.isTextEntryFocused = isFocused
                    if wasFocused, !isFocused, editingPlaylistID == playlist.id {
                        commitRename(playlist, proposed: editDraft, keepOpenOnConflict: false)
                    }
                }
                .onDisappear { keyboardFocus.isTextEntryFocused = false }
                // Focus HERE, in the field's own onAppear — reliable post-insertion (the field is in
                // the hierarchy), unlike a @FocusState set from beginRename which bounced on a
                // freshly-inserted LazyVStack row and let the blur handler self-close the field.
                .onAppear { renameFieldFocused = true }
                // Capture the draft SYNCHRONOUSLY at submit: a later blur/teardown that clears
                // `editDraft` must not race the async rename into an empty/stale name.
                .onSubmit { commitRename(playlist, proposed: editDraft, keepOpenOnConflict: true) }
                .onExitCommand { cancelRename() }
                .padding(.horizontal, DesignSystem.Spacing.small)
                .padding(.vertical, 5)
            if let renameError {
                Text(renameError)
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(.red)
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

    /// Create a new untitled playlist, select it, and drop straight into inline-rename (Apple-style).
    private func createAndBeginRename() async {
        guard let id = await playlists.createPlaylist() else { return }
        model.selectPlaylist(id)
        if let created = playlists.playlists.first(where: { $0.id == id }) { beginRename(created) }
    }

    private func beginRename(_ playlist: Playlist) {
        editDraft = playlist.name
        renameError = nil
        editingPlaylistID = playlist.id
        // Focus is set by the rename field's own `.onAppear` (reliable once it's in the hierarchy) —
        // NOT here, where the field doesn't exist yet and @FocusState would bounce + self-close.
    }

    /// Begin renaming the selected playlist (keyboard Return). `.ignored` unless a playlist row is
    /// the current selection, so the event bubbles for categories / drill-downs.
    private func renameSelectedPlaylist() -> KeyPress.Result {
        guard case let .playlist(id) = model.sidebarSelection,
              let playlist = playlists.playlists.first(where: { $0.id == id }) else { return .ignored }
        beginRename(playlist)
        return .handled
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

    /// Commit the rename from a draft captured synchronously at submit time (`proposed`). Empty or
    /// unchanged → cancel (no write). On a duplicate name (D-names: globally unique): when committing
    /// via Return (`keepOpenOnConflict`) the field stays open with an inline message; on click-away
    /// it reverts silently (don't trap a user who's leaving). Guarded so a stale/torn-down field
    /// can't commit.
    private func commitRename(_ playlist: Playlist, proposed: String, keepOpenOnConflict: Bool) {
        guard editingPlaylistID == playlist.id else { return }
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != playlist.name else { cancelRename(); return }
        Task {
            do {
                try await playlists.renamePlaylist(id: playlist.id, to: name)
                // The user may have begun renaming ANOTHER row during the await — only close if THIS
                // playlist is still the one being edited (QA break-it #5).
                if editingPlaylistID == playlist.id { cancelRename() }
            } catch let conflict as PlaylistNameConflict where keepOpenOnConflict {
                renameError = "“\(conflict.name)” already exists."
                renameFieldFocused = true
            } catch PlaylistMutationError.invalidName where keepOpenOnConflict {
                renameError = "That name can’t be used." // reserved ("current") — empty is pre-guarded
                renameFieldFocused = true
            } catch {
                if keepOpenOnConflict {
                    renameError = "Couldn’t rename this playlist."
                    renameFieldFocused = true
                } else {
                    cancelRename() // leaving the field: revert rather than trap on the error
                }
            }
        }
    }

    private func cancelRename() {
        editingPlaylistID = nil
        editDraft = ""
        renameError = nil
        keyboardFocus.isTextEntryFocused = false
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
        .background(.bar)
    }
}
