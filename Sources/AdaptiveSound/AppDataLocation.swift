import Foundation

// MARK: - Where the app persists

/// Everything the app persists, in one place: the library store (tracks, albums, playlists, the
/// queue, play history and the watched music folders all live in it), its artwork cache, the
/// settings (EQ, the queue cursor, every `@AppStorage` key), and the single-instance lock.
///
/// Decided ONCE, at launch (`AdaptiveSound.init`), and injected into every model that persists;
/// `@AppStorage` reads it through `.defaultAppStorage`. Nothing else names Application Support or
/// the standard defaults (semgrep `persist-one-location`).
struct AppDataLocation {
    /// The folder under Application Support holding the store, the artwork cache and the lock.
    let directory: URL
    /// Every settings read and write: the view models' and every `@AppStorage`'s.
    let defaults: UserDefaults

    /// The library store file (GRDB keeps its `-wal` / `-shm` sidecars, and quarantines a corrupt
    /// file, beside it).
    var storeURL: URL {
        directory.appending(path: "library.sqlite3", directoryHint: .notDirectory)
    }

    /// The content-addressed cover-art cache (originals + thumbnails), a sibling of the store.
    var artworkCacheURL: URL {
        directory.appending(path: "artwork", directoryHint: .isDirectory)
    }

    /// The single-instance lock: one running copy per location.
    var instanceLockURL: URL {
        directory.appending(path: "instance.lock", directoryHint: .notDirectory)
    }

    /// This launch's location, its folder created if missing.
    static func atLaunch() -> AppDataLocation {
        let location = user
        // A failure surfaces where it matters: the store reports it, and the lock lets the launch go on.
        try? FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        return location
    }

    /// The user's own library: `~/Library/Application Support/AdaptiveSound/` and the app's
    /// standard defaults.
    private static var user: AppDataLocation {
        AppDataLocation(directory: applicationSupport("AdaptiveSound"), defaults: .standard)
    }

    /// `~/Library/Application Support/<folderName>/`.
    private static func applicationSupport(_ folderName: String) -> URL {
        URL.applicationSupportDirectory.appending(path: folderName, directoryHint: .isDirectory)
    }
}
