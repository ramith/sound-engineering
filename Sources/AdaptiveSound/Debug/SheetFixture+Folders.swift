#if DEBUG
    import Foundation
    import LibraryScan
    import LibraryStore

    // MARK: - Picture-sheet fixture data: the Music Folders rail (R1.1-A, KI-LIB-02)

    extension SheetFixture {
        /// The folder-paused world's music folders, as the rail lists them: one on the Mac, watched;
        /// one on a drive that is unplugged; one the app may not open — the paused look next to the
        /// normal one, with the shortest reason and the longest.
        static func seedPausedFolders(_ browse: LibraryBrowseModel, library: LibraryModel) {
            let home = NSHomeDirectory()
            browse.seedRenderFixture(roots: [
                LibraryFolder(id: 1, path: home + "/Music"),
                LibraryFolder(id: 2, path: "/Volumes/T7/Music"),
                LibraryFolder(id: 3, path: home + "/Shared/Lossless"),
            ])
            library.reconcileState = [
                1: .watching,
                2: .paused(SweepRefusal.Reason.rootVanished),
                3: .paused(SweepRefusal.Reason.incompleteWalk),
            ]
        }

        /// The folder-checking world's music folders: one on the Mac, watched; the one "Use This Drive…" was
        /// chosen for and the other paused folder of its drive, both being checked on the drive chosen.
        static func seedCheckingFolders(_ browse: LibraryBrowseModel, library: LibraryModel) {
            browse.seedRenderFixture(roots: [
                LibraryFolder(id: 1, path: NSHomeDirectory() + "/Music"),
                LibraryFolder(id: 2, path: "/Volumes/T7/Music"),
                LibraryFolder(id: 3, path: "/Volumes/T7/Live"),
            ])
            library.reconcileState = [
                1: .watching,
                2: .paused(SweepRefusal.Reason.rootVanished),
                3: .paused(SweepRefusal.Reason.rootVanished),
            ]
            library.checkingDriveFolderIDs = [2, 3]
        }
    }
#endif
