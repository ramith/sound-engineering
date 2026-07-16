import LibraryStore
import SwiftUI

// MARK: - LibrarySidebar + inline rename (split out for type-body length)

/// The playlist inline-rename flow (design §4). A same-type extension — split from `LibrarySidebar`
/// for file/type-body length, like `+Facets`/`+Play`. Reaches the sidebar's `internal` rename state.
/// The transport-Space gate is owned by the field's `.suppressesTransportSpace(while:)` modifier, so
/// `cancelRename` no longer clears it by hand.
extension LibrarySidebar {
    /// Create a new untitled playlist, select it, and drop straight into inline-rename (Apple-style).
    func createAndBeginRename() async {
        guard let id = await playlists.createPlaylist() else { return }
        model.selectPlaylist(id)
        if let created = playlists.playlists.first(where: { $0.id == id }) { beginRename(created) }
    }

    func beginRename(_ playlist: Playlist) {
        // Re-entry guard: a rename already in progress for THIS playlist must NOT restart — that would
        // reset `editDraft` and wipe the user's in-progress typing (observed: a hijacked Return
        // re-invoked this and clobbered the name; see the editing-gated `.onKeyPress` handlers).
        guard editingPlaylistID != playlist.id else { return }
        editDraft = playlist.name
        renameError = nil
        editingPlaylistID = playlist.id
        // Yield the sidebar's key focus so the rename TextField (focused in its own `.onAppear`) owns
        // Return/arrows — otherwise the ScrollView's `.onKeyPress` handlers intercept them. Restored
        // on the keyboard close paths (`commitRename`/`onExitCommand`) so ↑/↓ stay alive after.
        sidebarFocused = false
    }

    /// Begin renaming the selected playlist (keyboard Return). `.ignored` unless a playlist row is
    /// the current selection, so the event bubbles for categories / drill-downs.
    func renameSelectedPlaylist() -> KeyPress.Result {
        guard case let .playlist(id) = model.sidebarSelection,
              let playlist = playlists.playlists.first(where: { $0.id == id }) else { return .ignored }
        beginRename(playlist)
        return .handled
    }

    /// Commit the rename from a draft captured synchronously at submit time (`proposed`). Empty or
    /// unchanged → cancel (no write). On a duplicate name (D-names: globally unique): when committing
    /// via Return (`keepOpenOnConflict`) the field stays open with an inline message; on click-away
    /// it reverts silently (don't trap a user who's leaving). Guarded so a stale/torn-down field
    /// can't commit.
    func commitRename(_ playlist: Playlist, proposed: String, keepOpenOnConflict: Bool) {
        guard editingPlaylistID == playlist.id else { return }
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        // `keepOpenOnConflict` distinguishes the KEYBOARD paths (Return) from click-away, so it
        // doubles as "restore list focus on close" — a keyboard close keeps ↑/↓/Return alive.
        guard !name.isEmpty, name != playlist.name else {
            finishRename(restoreListFocus: keepOpenOnConflict)
            return
        }
        Task {
            do {
                try await playlists.renamePlaylist(id: playlist.id, to: name)
                // The user may have begun renaming ANOTHER row during the await — only close if THIS
                // playlist is still the one being edited (QA break-it #5).
                if editingPlaylistID == playlist.id { finishRename(restoreListFocus: keepOpenOnConflict) }
            } catch let conflict as PlaylistNameConflict where keepOpenOnConflict {
                showRenameError("“\(conflict.name)” already exists.")
            } catch PlaylistMutationError.invalidName where keepOpenOnConflict {
                showRenameError("That name can’t be used.") // reserved ("current") — empty is pre-guarded
            } catch {
                if keepOpenOnConflict {
                    showRenameError("Couldn’t rename this playlist.")
                } else {
                    cancelRename() // leaving the field: revert rather than trap on the error
                }
            }
        }
    }

    /// Close the rename field; on a KEYBOARD close (Return/Escape) restore list focus so ↑/↓ stay
    /// alive — NOT on click-away, where the user intentionally moved focus elsewhere (focus-audit).
    func finishRename(restoreListFocus: Bool) {
        cancelRename()
        if restoreListFocus { sidebarFocused = true }
    }

    /// Surface an inline rename error + keep the field open/focused for a retry.
    func showRenameError(_ message: String) {
        renameError = message
        renameFieldFocused = true
    }

    func cancelRename() {
        editingPlaylistID = nil
        editDraft = ""
        renameError = nil
    }
}
