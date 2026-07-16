import LibraryStore

// MARK: - PlaylistBrowseVisibility (S10.3 — built-in exclusion, pure + testable)

/// Decides which playlists appear in the browse UI. The built-in "current" queue playlist
/// (`is_builtin = 1`) is invisible + inert everywhere (D-store) — only user playlists show in the
/// sidebar. Extracted as a pure function (design §5) so the "built-in never leaks" invariant is
/// unit-testable, rather than an inline `!$0.isBuiltin` filter that no test can pin.
public enum PlaylistBrowseVisibility {
    /// Whether a single playlist is user-visible (i.e. NOT the built-in).
    public static func isUserVisible(_ playlist: Playlist) -> Bool {
        !playlist.isBuiltin
    }

    /// The user-visible subset, order preserved (the built-in is dropped wherever it sits).
    public static func userVisible(_ playlists: [Playlist]) -> [Playlist] {
        playlists.filter(isUserVisible)
    }
}
