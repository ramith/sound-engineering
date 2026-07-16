import LibraryBrowseKit
import Testing

// MARK: - PlaylistAddDecision (S10.3 — order / dedupe / toast)

@Suite("PlaylistAddDecision — order, dedupe, toast")
struct PlaylistAddDecisionTests {
    /// ADD-1 — the selection is de-duplicated, first-seen order preserved.
    @Test("dedupe selection, keep first-seen order")
    func dedupePreservesOrder() {
        #expect(PlaylistAddDecision.trackIDsToAdd([3, 1, 3, 2, 1]) == [3, 1, 2])
    }

    /// ADD-2 — empty selection → empty (no-op add).
    @Test("empty → empty")
    func empty() {
        #expect(PlaylistAddDecision.trackIDsToAdd([]).isEmpty)
    }

    /// ADD-3 — toast copy: pluralization + nil for a no-op.
    @Test("toast copy + no-op silence")
    func toast() {
        #expect(PlaylistAddDecision.toastMessage(added: 1, playlistName: "Rock") == "Added 1 song to “Rock”")
        #expect(PlaylistAddDecision.toastMessage(added: 3, playlistName: "Rock") == "Added 3 songs to “Rock”")
        #expect(PlaylistAddDecision.toastMessage(added: 0, playlistName: "Rock") == nil)
    }
}
