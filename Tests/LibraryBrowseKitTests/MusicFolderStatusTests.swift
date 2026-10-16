import LibraryBrowseKit
import LibraryScan
import Testing

// MARK: - What a Music Folders row says under its path (R1.1-A, KI-LIB-02; founder 2026-10-15)

/// A paused folder — its last walk was refused (`SweepRefusal`), so its songs are kept — says why, in
/// the founder's words, in the caption slot "Scanning…" uses. These pin the words for every refusal
/// reason, that a running scan wins the slot, and that any other folder says nothing.
@Suite("A Music Folders row says why its folder is paused (KI-LIB-02)")
struct MusicFolderStatusTests {
    @Test("each refusal reason has its own short caption", arguments: [
        (SweepRefusal.Reason.rootVanished, "Not found — is its drive connected?"),
        (.differentVolume, "Another drive is using this name"),
        (.unrecognizedFolder, "Can’t confirm this is the folder’s drive"),
        (.incompleteWalk, "Can’t open this folder — check its permissions"),
        (.emptyWalk, "Looks empty — songs kept"),
    ])
    func pausedCaption(reason: SweepRefusal.Reason, caption: String) throws {
        let status = try #require(MusicFolderStatus(isScanning: false, pausedBy: reason))
        #expect(status == .paused(reason))
        #expect(status.caption == caption)
        #expect(status.isPaused)
    }

    @Test("a running scan wins the caption slot, and is not the paused look")
    func scanningWins() throws {
        let status = try #require(MusicFolderStatus(isScanning: true, pausedBy: .rootVanished))
        #expect(status == .scanning)
        #expect(status.caption == "Scanning…")
        #expect(!status.isPaused)
    }

    @Test("a folder neither scanning nor paused says nothing")
    func quietFolder() {
        #expect(MusicFolderStatus(isScanning: false, pausedBy: nil) == nil)
    }

    @Test("the paused tooltip says the songs stay and come back")
    func pausedHelp() {
        #expect(MusicFolderStatus.pausedHelp
            == "Its songs stay in your library and playlists, and come back when it’s back.")
    }
}
