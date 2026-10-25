import LibraryBrowseKit
import LibraryScan
import LibraryStore
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

    /// "Use This Drive…" (R1.1-B, US-R1F-03 LIB-VOL-1; plan check §6 counter-example 9): offered only for a
    /// folder whose drive is gone, replaced or unconfirmed — never one the app can't open or that walked empty.
    @Test("“Use This Drive…” is offered for a gone, replaced or unconfirmed drive only", arguments: [
        (SweepRefusal.Reason.rootVanished, true), (.differentVolume, true), (.unrecognizedFolder, true),
        (.incompleteWalk, false), (.emptyWalk, false),
    ])
    func offersUseThisDrive(reason: SweepRefusal.Reason, offered: Bool) throws {
        let status = try #require(MusicFolderStatus(isScanning: false, pausedBy: reason))
        #expect(status.offersUseThisDrive == offered)
    }

    @Test("a folder being scanned is not offered another drive")
    func scanningNotOffered() throws {
        let status = try #require(MusicFolderStatus(isScanning: true, pausedBy: .rootVanished))
        #expect(!status.offersUseThisDrive)
    }

    @Test("after “Use This Drive…”, the app says what it kept and removed — or that it is the wrong drive")
    func rebindMessages() {
        #expect(MusicFolderStatus.rebindMessage(.rebound(kept: 1234, removed: 0), folderName: "Music")
            == "“Music” now uses this drive — all 1,234 songs found.")
        #expect(MusicFolderStatus.rebindMessage(.rebound(kept: 8, removed: 2), folderName: "Music")
            == "“Music” now uses this drive — 8 songs found; 2 that aren’t on it were removed.")
        #expect(MusicFolderStatus.rebindMessage(.rebound(kept: 1, removed: 1), folderName: "Music")
            == "“Music” now uses this drive — 1 song found; 1 that isn’t on it was removed.")
        #expect(MusicFolderStatus.rebindMessage(.refused(.noSongsFound), folderName: "Music")
            == "That’s not the drive for “Music” — none of its songs are on it. Nothing was changed.")
        #expect(MusicFolderStatus.rebindMessage(.refused(.notAFolder), folderName: "Music") == nil)
    }
}
