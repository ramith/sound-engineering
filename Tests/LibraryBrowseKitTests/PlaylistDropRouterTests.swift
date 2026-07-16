import LibraryBrowseKit
import Testing

// MARK: - PlaylistDropRouter (S10.3 — a drop onto a playlist is ADD-ONLY, never a file op)

@Suite("PlaylistDropRouter — add-only routing")
struct PlaylistDropRouterTests {
    /// DROP-1 — a drop of track ids routes to `.addTracks`, de-duplicated in first-seen order. The
    /// outcome type has no move/copy case, so "a drop never touches the filesystem" is structural.
    @Test("drop routes to add-only, deduped + ordered")
    func routesToAddOnly() {
        #expect(PlaylistDropRouter.route(droppedTrackIDs: [7, 3, 7, 9, 3]) == .addTracks([7, 3, 9]))
    }

    /// DROP-2 — an empty drop is a no-op add (empty ids), never nil / never a file op.
    @Test("empty drop → add nothing")
    func emptyDrop() {
        #expect(PlaylistDropRouter.route(droppedTrackIDs: []) == .addTracks([]))
    }
}
