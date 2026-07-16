import LibraryBrowseKit
import LibraryStore
import Testing

// MARK: - PlaylistBrowseVisibility (S10.3 — built-in never leaks into the browse UI)

@Suite("PlaylistBrowseVisibility — built-in exclusion")
struct PlaylistBrowseVisibilityTests {
    private func playlist(_ id: Int64, _ name: String, builtin: Bool) -> Playlist {
        Playlist(id: id, name: name, isBuiltin: builtin, createdAt: 0, entryCount: 0)
    }

    /// VIS-1 — the built-in "current" playlist is never user-visible; a user playlist always is.
    @Test("built-in excluded, user included")
    func singlePredicate() {
        #expect(PlaylistBrowseVisibility.isUserVisible(playlist(1, "current", builtin: true)) == false)
        #expect(PlaylistBrowseVisibility.isUserVisible(playlist(2, "Rock", builtin: false)) == true)
    }

    /// VIS-2 — filtering drops the built-in wherever it sits and preserves the order of the rest.
    @Test("userVisible drops built-in, preserves order")
    func filterPreservesOrder() {
        let input = [
            playlist(10, "A", builtin: false),
            playlist(1, "current", builtin: true),
            playlist(11, "B", builtin: false),
        ]
        let visible = PlaylistBrowseVisibility.userVisible(input)
        #expect(visible.map(\.id) == [10, 11])
    }

    /// VIS-3 — an all-built-in (or empty) input yields nothing.
    @Test("only built-in → empty")
    func onlyBuiltin() {
        #expect(PlaylistBrowseVisibility.userVisible([playlist(1, "current", builtin: true)]).isEmpty)
        #expect(PlaylistBrowseVisibility.userVisible([]).isEmpty)
    }
}
