import LibraryScan
import Testing

// MARK: - Where a drive's other folders are now (plan check §6, "Use this drive" (10); R1.1-B fix round)

/// One "Use This Drive…" choice moves the paused folders of the same drive along (`LibraryModel.useDrive`):
/// each is looked for at its own place on the drive as mounted now. The part the chosen folder's old and new
/// paths END with in common is its place on the drive; what comes before is where the drive was and is.
@Suite("“Use this drive” — where the drive's other folders are now")
struct RootRebinderLocationTests {
    @Test("a new mount name: a folder of the drive is at its place under the new name", arguments: [
        ("/Volumes/Music/Jazz", "/Volumes/Music 1/Jazz"),
        ("/Volumes/Music/Live/2019", "/Volumes/Music 1/Live/2019"),
        ("/Volumes/Music", "/Volumes/Music 1"),
    ])
    func newMountName(folder: String, now: String) {
        #expect(RootRebinder.location(of: folder, movedFrom: "/Volumes/Music/Rock", to: "/Volumes/Music 1/Rock") == now)
    }

    @Test("the same path on a new drive: every folder of the drive is where it was")
    func samePath() {
        #expect(RootRebinder.location(of: "/Volumes/T7/Jazz", movedFrom: "/Volumes/T7/Rock", to: "/Volumes/T7/Rock")
            == "/Volumes/T7/Jazz")
    }

    @Test("a copy into another folder: the drive's folders are under it")
    func copiedElsewhere() {
        #expect(RootRebinder.location(of: "/Volumes/T7/Jazz", movedFrom: "/Volumes/T7/Music",
                                      to: "/Users/me/Backup/Music") == "/Users/me/Backup/Jazz")
    }

    @Test("a folder not under where the drive was has no place on it", arguments: [
        "/Volumes/Other/Jazz", "/Volumes/MusicBox/Jazz", "/Users/me/Music",
    ])
    func notOnTheDrive(folder: String) {
        #expect(RootRebinder.location(of: folder, movedFrom: "/Volumes/Music/Rock", to: "/Volumes/Music 1/Rock") == nil)
    }

    @Test("a folder renamed when chosen: only folders inside its old path have a place")
    func renamedFolder() {
        #expect(RootRebinder.location(of: "/Volumes/Music/Jazz", movedFrom: "/Volumes/Music/Rock",
                                      to: "/Volumes/T7/Rock Copy") == nil)
        #expect(RootRebinder.location(of: "/Volumes/Music/Rock/Live", movedFrom: "/Volumes/Music/Rock",
                                      to: "/Volumes/T7/Rock Copy") == "/Volumes/T7/Rock Copy/Live")
    }
}
